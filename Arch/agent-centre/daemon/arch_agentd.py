#!/usr/bin/env python3
"""arch-agentd — Agent Centre backend for Arch Shell.

Stdlib only. Local JSON API for the Quickshell UI.

    GET  /health
    GET  /state
    GET  /models?provider=google
    GET  /chat
    POST /chat/send             {text, provider?, model?}
    POST /chat/setup            {provider?, model?}
    POST /chat/clear
    POST /teams                 {name, parentId?, rules?, approval?, comms?}
    POST /teams/update          {id, name?, parentId?, rules?, approval?,
                                 comms?, leadAgentId?}
    POST /teams/delete          {id}
    POST /agents                {team, name, role, repo, provider, model,
                                 rank?, reportsTo?, rules?, approval?}
    POST /agents/update         {id, ...fields}
    POST /agents/delete         {id}
    POST /agents/task           {id, task}
    POST /agents/message        {from, to, text}   to = agent id | team:<id>
    POST /providers             {name, key}
    POST /providers/login       {name, action=start|import|cancel}
    POST /providers/delete      {name}
    POST /permissions/resolve   {id, approve, sudoPassword?}
    POST /activity/clear
"""

from __future__ import annotations

import json
import os
import queue
import re
import subprocess
import sys
import threading
import time
import urllib.parse
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

_DAEMON_DIR = Path(__file__).resolve().parent
if str(_DAEMON_DIR) not in sys.path:
    sys.path.insert(0, str(_DAEMON_DIR))

from providers_auth import (  # noqa: E402
    PROVIDER_DEFAULTS,
    RETIRED_MODELS,
    ProviderError,
    call_provider as auth_call_provider,
    cancel_login,
    canonical_provider,
    import_existing,
    list_models,
    peek_models,
    public_provider,
    start_login,
    take_finished_login,
)

HOST = "127.0.0.1"
PORT = int(os.environ.get("ARCH_AGENTD_PORT", "8787"))

# Generate calls should fail fast. Thinking models used to sit here for 120s.
HTTP_TIMEOUT = int(os.environ.get("ARCH_AGENTD_HTTP_TIMEOUT", "30"))
LIST_TIMEOUT = 12

CONFIG_DIR = Path(os.environ.get("ARCH_SHELL_CONFIG",
                                 Path.home() / ".config" / "arch-shell")) / "agent"
STATE_FILE = CONFIG_DIR / "state.json"
PROVIDERS_FILE = CONFIG_DIR / "providers.json"
CHAT_FILE = CONFIG_DIR / "chat.json"
MAX_CHAT_MESSAGES = 40

MAX_ACTIVITY = 200
MAX_HOPS = 8
MAX_WRITE = 1_000_000
SHELL_TIMEOUT = 30
SUDO_TIMEOUT = 180
HOME = Path.home().resolve()

DUTIES = ("implement", "review", "coordinate")
RANK_NAMES = {0: "worker", 1: "lead", 2: "director"}
APPROVAL_MODES = ("inherit", "user", "higher", "auto")
COMMS_MODES = ("isolated", "team", "org", "open")
RULE_PRESETS = [
    "ask-before-commit",
    "ask-before-shell",
    "ask-before-network",
    "no-destructive",
    "stay-in-repo",
    "report-to-lead",
]

_lock = threading.RLock()
_work: "queue.Queue[tuple]" = queue.Queue()
_model_ok: dict[str, str] = {}  # provider → last model that succeeded


# ── storage ─────────────────────────────────────────────────────────────
def _blank_state() -> dict:
    return {"teams": [], "agents": [], "activity": [], "pending": []}


def _norm_team(raw: dict) -> dict:
    t = {
        "id": raw.get("id") or uuid.uuid4().hex[:8],
        "name": (raw.get("name") or "Team").strip(),
        "created": raw.get("created") or time.strftime("%Y-%m-%d"),
        "parentId": raw.get("parentId") or "",
        "leadAgentId": raw.get("leadAgentId") or "",
        "rules": list(raw.get("rules") or []),
        "approval": raw.get("approval") if raw.get("approval") in APPROVAL_MODES
                    and raw.get("approval") != "inherit" else "user",
        "comms": raw.get("comms") if raw.get("comms") in COMMS_MODES else "team",
        "brief": (raw.get("brief") or "").strip(),
    }
    return t


def _norm_agent(raw: dict) -> dict:
    provider = canonical_provider(raw.get("provider") or "openai")
    model = (raw.get("model") or "").strip()
    retired = RETIRED_MODELS.get(provider, set())
    if model in retired:
        model = ""
    rank = raw.get("rank", 0)
    try:
        rank = max(0, min(2, int(rank)))
    except (TypeError, ValueError):
        rank = 0
    approval = raw.get("approval") or "inherit"
    if approval not in APPROVAL_MODES:
        approval = "inherit"
    duties = [d for d in (raw.get("duties") or []) if d in DUTIES]
    return {
        "id": raw.get("id") or uuid.uuid4().hex[:8],
        "name": (raw.get("name") or "Agent").strip(),
        "role": (raw.get("role") or "Developer").strip(),
        "repo": (raw.get("repo") or "").strip(),
        "provider": provider,
        "model": model,
        "resolvedModel": raw.get("resolvedModel") or "",
        "teamId": raw.get("teamId") or "",
        "team": raw.get("team") or "",
        "rank": rank,
        "reportsTo": raw.get("reportsTo") or "",
        "rules": list(raw.get("rules") or ["ask-before-commit"]),
        "approval": approval,
        "brief": (raw.get("brief") or "").strip(),
        "duties": duties,
        "status": raw.get("status") or "idle",
        "task": raw.get("task") or "",
        "lastReply": raw.get("lastReply") or "",
    }


def load_state() -> dict:
    try:
        with STATE_FILE.open(encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return _blank_state()
    return {
        "teams": [_norm_team(t) for t in data.get("teams") or []],
        "agents": [_norm_agent(a) for a in data.get("agents") or []],
        "activity": list(data.get("activity") or []),
        "pending": list(data.get("pending") or []),
    }


def save_state(state: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2)
    tmp.replace(STATE_FILE)


def load_providers() -> dict:
    try:
        with PROVIDERS_FILE.open(encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def save_providers(providers: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = PROVIDERS_FILE.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        json.dump(providers, fh, indent=2)
    tmp.replace(PROVIDERS_FILE)
    try:
        os.chmod(PROVIDERS_FILE, 0o600)
    except OSError:
        pass


STATE = load_state()
for _agent in STATE["agents"]:
    if _agent.get("status") == "working":
        _agent["status"] = "idle"


def log(kind: str, text: str, agent: str = "", team: str = "") -> None:
    with _lock:
        STATE["activity"].insert(0, {
            "id": uuid.uuid4().hex[:8],
            "kind": kind,
            "text": text[:2000],
            "agent": agent,
            "team": team,
            "at": time.strftime("%H:%M:%S"),
        })
        del STATE["activity"][MAX_ACTIVITY:]
        save_state(STATE)


def find(items: list, ident: str) -> dict | None:
    if not ident:
        return None
    for item in items:
        if item.get("id") == ident:
            return item
    return None


def find_named(items: list, name: str) -> dict | None:
    if not name:
        return None
    needle = name.strip().lower()
    for item in items:
        if (item.get("name") or "").strip().lower() == needle:
            return item
    return None


def list_provider_models(provider: str) -> list[str]:
    return list_models(canonical_provider(provider),
                       load_providers().get(canonical_provider(provider)) or {})


def call_provider(provider: str, model: str, system: str, prompt: str) -> str:
    return auth_call_provider(
        load_providers(), provider, model, system, prompt, _model_ok)


# ── hierarchy ───────────────────────────────────────────────────────────
def team_of(agent: dict) -> dict | None:
    return find(STATE["teams"], agent.get("teamId") or "")


def ancestor_ids(team: dict | None) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    cur = team
    while cur and cur["id"] not in seen:
        out.append(cur["id"])
        seen.add(cur["id"])
        cur = find(STATE["teams"], cur.get("parentId") or "")
    return out


def related_team_ids(team: dict | None) -> set[str]:
    if not team:
        return set()
    ids = set(ancestor_ids(team))
    for other in STATE["teams"]:
        if team["id"] in ancestor_ids(other):
            ids.add(other["id"])
    return ids


def effective_rules(agent: dict) -> list[str]:
    team = team_of(agent)
    seen: list[str] = []
    for rule in list((team or {}).get("rules") or []) + list(agent.get("rules") or []):
        if rule and rule not in seen:
            seen.append(rule)
    return seen


def effective_approval(agent: dict) -> str:
    mode = agent.get("approval") or "inherit"
    if mode == "inherit":
        team = team_of(agent)
        mode = (team or {}).get("approval") or "user"
    return mode if mode in ("user", "higher", "auto") else "user"


def effective_comms(agent: dict) -> str:
    team = team_of(agent)
    mode = (team or {}).get("comms") or "team"
    return mode if mode in COMMS_MODES else "team"


def find_supervisor(agent: dict) -> dict | None:
    reports = find(STATE["agents"], agent.get("reportsTo") or "")
    if reports and reports["id"] != agent["id"]:
        return reports
    team = team_of(agent)
    if team and team.get("leadAgentId") and team["leadAgentId"] != agent["id"]:
        lead = find(STATE["agents"], team["leadAgentId"])
        if lead:
            return lead
    peers = [a for a in STATE["agents"]
             if a.get("teamId") == agent.get("teamId") and a["id"] != agent["id"]]
    higher = [a for a in peers if int(a.get("rank") or 0) > int(agent.get("rank") or 0)]
    if higher:
        higher.sort(key=lambda a: int(a.get("rank") or 0), reverse=True)
        return higher[0]
    if team and team.get("parentId"):
        parent = find(STATE["teams"], team["parentId"])
        if parent and parent.get("leadAgentId"):
            lead = find(STATE["agents"], parent["leadAgentId"])
            if lead and lead["id"] != agent["id"]:
                return lead
    return None


def find_reports_to(agent: dict | None) -> dict | None:
    if not agent:
        return None
    dest = find(STATE["agents"], agent.get("reportsTo") or "")
    if dest and dest["id"] != agent["id"]:
        return dest
    return None


def _is_reviewer(agent: dict) -> bool:
    return "review" in agent_duties(agent)


def find_peer_reviewer(agent: dict) -> dict | None:
    """Coder's sibling reviewer under the same lead, if any."""
    if _is_reviewer(agent):
        return None
    lead_id = agent.get("reportsTo") or ""
    if not lead_id:
        return None
    for other in STATE["agents"]:
        if other["id"] == agent["id"]:
            continue
        if other.get("reportsTo") == lead_id and "review" in agent_duties(other):
            return other
    return None


def find_peer_coder(agent: dict) -> dict | None:
    lead_id = agent.get("reportsTo") or ""
    if not lead_id:
        return None
    for other in STATE["agents"]:
        if other["id"] == agent["id"] or "review" in agent_duties(other):
            continue
        if other.get("reportsTo") == lead_id and "implement" in agent_duties(other):
            return other
    return None


def can_talk(src: dict, dest: dict) -> bool:
    """May `src` agent message `dest` (agent or team)?"""
    mode = effective_comms(src)
    if mode == "open":
        return True
    src_team = src.get("teamId") or ""
    dest_is_team = "comms" in dest or "leadAgentId" in dest
    dest_team = dest["id"] if dest_is_team else (dest.get("teamId") or "")
    if dest.get("id") == src.get("reportsTo"):
        return True
    # Peers under the same lead (coder ↔ reviewer) may always talk.
    if (not dest_is_team and src.get("reportsTo")
            and src.get("reportsTo") == dest.get("reportsTo")):
        return True
    if mode == "isolated":
        return dest.get("id") == src.get("reportsTo")
    if mode == "team":
        return dest_team == src_team
    if mode == "org":
        return dest_team in related_team_ids(team_of(src))
    return False


def can_assign(src: dict, dest: dict) -> bool:
    """Only down the reporting line — director → lead → worker."""
    if dest["id"] == src["id"]:
        return False
    if not can_talk(src, dest):
        return False
    return dest.get("reportsTo") == src["id"]


# ── permissions & actions ───────────────────────────────────────────────
def _public_payload(payload: dict) -> dict:
    out = dict(payload or {})
    for key in _SECRET_KEYS:
        out.pop(key, None)
    return out


def _elevation_kind(action: dict) -> str:
    if action.get("sudo") is True or str(action.get("sudo") or "").lower() in (
            "1", "yes", "true"):
        return "sudo"
    cmd = action.get("command") or action.get("cmd") or ""
    match = _ELEVATION_TOKEN.search(cmd)
    return match.group(1).lower() if match else ""


def _sudo_cached() -> bool:
    try:
        return subprocess.run(
            ["sudo", "-n", "true"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        ).returncode == 0
    except Exception:
        return False


def _permission_flags(payload: dict) -> dict:
    kind = _elevation_kind(payload)
    needs = bool(payload.get("needsSudo") or kind)
    elevate = kind or ("sudo" if needs else "")
    return {
        "needsSudo": needs,
        "elevation": elevate,
        "sudoNeedsPassword": bool(
            needs and elevate == "sudo" and not _sudo_cached()),
    }


def _scrub_secret(text: str, secret: str) -> str:
    if not text or not secret:
        return text or ""
    return text.replace(secret, "***")


def _append_chat_note(text: str) -> None:
    with _lock:
        chat = load_chat()
        chat["messages"].append({
            "role": "assistant",
            "content": text,
            "at": time.strftime("%H:%M:%S"),
        })
        chat["messages"] = chat["messages"][-MAX_CHAT_MESSAGES:]
        save_chat(chat)


def _live_agent(agent_id: str, fallback: dict | None = None) -> dict | None:
    if agent_id == "chat":
        return _chat_agent()
    return find(STATE["agents"], agent_id or "") or fallback


def request_permission(agent: dict, what: str, payload: dict,
                       approver: dict | None = None) -> dict:
    payload = _public_payload(payload)
    flags = _permission_flags(payload)
    if flags["needsSudo"]:
        payload["needsSudo"] = True
        payload["force_user"] = True
        approver = None
    if (approver is None and effective_approval(agent) == "higher"
            and not payload.get("force_user")):
        approver = find_peer_reviewer(agent) or find_reports_to(agent)
    if effective_approval(agent) == "auto" and not payload.get("force_user"):
        log("permission", f"Auto-approved: {agent.get('name')} {what}",
            agent.get("name", ""), agent.get("team", ""))
        return {"id": "", "auto": True, "approved": True}

    entry = {
        "id": uuid.uuid4().hex[:8],
        "agent": agent.get("name", ""),
        "agentId": agent.get("id", ""),
        "what": what,
        "payload": payload,
        "at": time.strftime("%H:%M:%S"),
        "approverKind": "agent" if approver else "user",
        "approverId": (approver or {}).get("id", ""),
        "approverName": (approver or {}).get("name", "you"),
        "status": "awaiting-agent" if approver else "awaiting-user",
        **flags,
    }
    with _lock:
        STATE["pending"].append(entry)
        save_state(STATE)
    log("permission",
        f"{agent.get('name')} {what} · awaiting {entry['approverName']}",
        agent.get("name", ""))
    _notify(f"{agent.get('name')} {what}")
    if approver:
        _work.put(("supervise", entry["id"]))
    return entry


def _notify(text: str, title: str = "Permission needed") -> None:
    try:
        subprocess.Popen(
            ["notify-send", "-a", "Agent Centre", title, text],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


class ToolError(RuntimeError):
    pass


TOOL_KINDS = ("write", "mkdir", "shell", "read")
TOOL_ALIASES = {
    "write_file": "write", "create_file": "write", "file": "write",
    "save": "write", "touch": "write",
    "make_dir": "mkdir", "makedir": "mkdir", "create_dir": "mkdir",
    "run": "shell", "exec": "shell", "command": "shell", "bash": "shell",
    "cat": "read", "open": "read",
}
NETWORK_CMDS = re.compile(
    r"\b(curl|wget|nc|ncat|nmap|ssh|scp|sftp|ftp|aria2c|httpie)\b", re.I)
ALWAYS_BLOCK = re.compile(
    r"(rm\s+(-[a-zA-Z]*f[a-zA-Z]*|--recursive)\s+(/|~/?\s|$)"
    r"|rm\s+-rf\s+\*"
    r"|\bmkfs\b|\bdd\s+if="
    r"|\b(shutdown|reboot|poweroff|halt)\b"
    r"|:\(\)\s*\{\s*:\s*\|\s*:\s*;\s*\})",
    re.I)
_ELEVATION_TOKEN = re.compile(r"(?:^|[;&|]\s*)(sudo|pkexec)\b", re.I)
_SECRET_KEYS = ("_sudo_password", "sudoPassword", "sudo_password")
WORK_HINTS = (
    "create", "write", "make a", "mkdir", "touch ", "save ",
    "file", "directory", "folder", "script", "hello world",
    "run ", "install", "put ", "drop ",
)


def _normalize_action(action: dict) -> dict:
    out = dict(action)
    kind = (out.get("type") or out.get("kind") or out.get("action") or "").lower()
    kind = TOOL_ALIASES.get(kind, kind)
    out["type"] = kind
    return out


def _iter_json_dicts(text: str):
    decoder = json.JSONDecoder()
    i = 0
    while True:
        start = text.find("{", i)
        if start < 0:
            return
        try:
            obj, end = decoder.raw_decode(text, start)
        except ValueError:
            i = start + 1
            continue
        if isinstance(obj, dict):
            yield obj, start, end
        i = end


def _split_actions(reply: str) -> tuple[str, list, bool]:
    """Return (visible text, actions, whether a JSON actions object was found)."""
    text = (reply or "").rstrip()
    actions: list = []
    if not text:
        return text, actions, False
    found = None
    span = None
    for obj, start, end in _iter_json_dicts(text):
        if "actions" in obj and isinstance(obj.get("actions"), list):
            found = list(obj.get("actions") or [])
            span = (start, end)
        elif (obj.get("type") or obj.get("kind") or "") in TOOL_KINDS or (
                TOOL_ALIASES.get((obj.get("type") or obj.get("kind") or "").lower())):
            found = [obj]
            span = (start, end)
    if found is None:
        return text, actions, False
    cleaned = (text[:span[0]] + text[span[1]:]).replace("```json", "").replace("```", "")
    return cleaned.strip(), found, True


def _task_looks_like_work(task: str) -> bool:
    t = (task or "").lower()
    return any(hint in t for hint in WORK_HINTS)


def _safe_path(agent: dict, raw: str) -> Path:
    raw = (raw or "").strip()
    if not raw:
        raise ToolError("missing path")
    if raw.startswith("~"):
        path = Path(os.path.expanduser(raw))
    else:
        path = Path(raw)
        if not path.is_absolute():
            repo = (agent.get("repo") or "").strip()
            base = Path(os.path.expanduser(repo)).resolve() if repo else HOME
            path = base / path
    path = path.resolve()
    repo = (agent.get("repo") or "").strip()
    repo_root = Path(os.path.expanduser(repo)).resolve() if repo else None
    allowed = [HOME]
    if repo_root:
        allowed.append(repo_root)
    if not any(path == root or root in path.parents for root in allowed):
        raise ToolError(f"path outside home/repo: {path}")
    forbidden = [
        HOME / ".ssh",
        HOME / ".gnupg",
        HOME / ".gpg",
        HOME / ".aws",
        CONFIG_DIR / "providers.json",
    ]
    for root in forbidden:
        root = root.resolve()
        if path == root or root in path.parents:
            raise ToolError(f"refusing to touch {path}")
    if "stay-in-repo" in effective_rules(agent):
        if not repo_root:
            raise ToolError("stay-in-repo is set but this agent has no repo")
        if path != repo_root and repo_root not in path.parents:
            raise ToolError(f"path outside repo {repo_root}: {path}")
    return path


def _tool_summary(action: dict) -> str:
    kind = action.get("type") or "act"
    if kind == "write":
        return f"wants to write {action.get('path') or action.get('file') or 'a file'}"
    if kind == "mkdir":
        return f"wants to create directory {action.get('path') or ''}".strip()
    if kind == "shell":
        cmd = (action.get("command") or action.get("cmd") or "")[:80]
        return f"wants to run `{cmd}`"
    if kind == "read":
        return f"wants to read {action.get('path') or ''}".strip()
    return f"wants to {kind}"


def _needs_tool_approval(agent: dict, action: dict) -> bool:
    kind = action.get("type") or ""
    if kind == "read":
        return False
    rules = effective_rules(agent)
    mode = effective_approval(agent)
    cmd = action.get("command") or action.get("cmd") or ""
    if kind == "shell" and _elevation_kind(action):
        return True
    if kind == "shell" and "ask-before-shell" in rules:
        return True
    if kind == "shell" and "ask-before-network" in rules and NETWORK_CMDS.search(cmd):
        return True
    if mode == "auto":
        return False
    return kind in TOOL_KINDS


def _tool_write(agent: dict, action: dict) -> str:
    path = _safe_path(agent, action.get("path") or action.get("file") or "")
    content = action.get("content")
    if content is None:
        content = action.get("contents")
    if content is None:
        content = action.get("text")
    if content is None:
        content = action.get("body")
    if content is None:
        raise ToolError("write is missing content")
    if not isinstance(content, str):
        content = json.dumps(content, indent=2)
    data = content.encode("utf-8")
    if len(data) > MAX_WRITE:
        raise ToolError(f"write too large ({len(data)} bytes)")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return f"Wrote {path} ({len(data)} bytes)."


def _tool_mkdir(agent: dict, action: dict) -> str:
    path = _safe_path(agent, action.get("path") or "")
    path.mkdir(parents=True, exist_ok=True)
    return f"Created directory {path}."


def _tool_read(agent: dict, action: dict) -> str:
    path = _safe_path(agent, action.get("path") or action.get("file") or "")
    if not path.is_file():
        raise ToolError(f"not a file: {path}")
    data = path.read_bytes()
    if len(data) > MAX_WRITE:
        raise ToolError("file too large to read")
    text = data.decode("utf-8", errors="replace")
    return f"Contents of {path}:\n{text[:8000]}"


def _tool_shell(agent: dict, action: dict, sudo_password: str = "") -> str:
    cmd = (action.get("command") or action.get("cmd") or "").strip()
    if not cmd:
        raise ToolError("shell is missing command")
    rules = effective_rules(agent)
    if ALWAYS_BLOCK.search(cmd):
        raise ToolError(f"blocked dangerous command: {cmd}")
    if "no-destructive" in rules and re.search(
            r"\b(rm|mv|dd|mkfs|chmod|chown|truncate)\b", cmd):
        raise ToolError(f"no-destructive blocks: {cmd}")
    if "ask-before-network" in rules and NETWORK_CMDS.search(cmd):
        raise ToolError(f"ask-before-network blocks: {cmd}")
    repo = (agent.get("repo") or "").strip()
    cwd = Path(os.path.expanduser(repo)).resolve() if repo else HOME
    if not cwd.is_dir():
        cwd = HOME
    elevate = _elevation_kind(action)
    password = sudo_password or ""
    timeout = SUDO_TIMEOUT if elevate else SHELL_TIMEOUT
    env = {**os.environ, "HOME": str(HOME)}
    try:
        if elevate == "sudo":
            env = {**env, "SUDO_PROMPT": ""}
            argv = ["sudo", "-S" if password else "-n", "-p", "",
                    "bash", "-lc", cmd]
            proc = subprocess.run(
                argv, input=(password.rstrip("\n") + "\n") if password else None,
                cwd=str(cwd), capture_output=True, text=True,
                timeout=timeout, env=env)
        elif elevate == "pkexec":
            proc = subprocess.run(
                cmd, shell=True, cwd=str(cwd),
                capture_output=True, text=True, timeout=timeout, env=env)
        else:
            proc = subprocess.run(
                cmd, shell=True, cwd=str(cwd),
                capture_output=True, text=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired as exc:
        raise ToolError(f"command timed out after {timeout}s") from exc
    out = ((proc.stdout or "") + (proc.stderr or "")).strip()
    out = _scrub_secret(out, password)
    if len(out) > 4000:
        out = out[:4000] + "\n…"
    if proc.returncode != 0:
        raise ToolError(
            f"`{cmd}` exited {proc.returncode}" + (f": {out}" if out else ""))
    return f"Ran `{cmd}`.\n{out}" if out else f"Ran `{cmd}`."


def _run_tool(agent: dict, action: dict, persist: bool = True,
              sudo_password: str = "") -> str:
    kind = action.get("type") or ""
    runners = {
        "write": _tool_write,
        "mkdir": _tool_mkdir,
        "read": _tool_read,
        "shell": _tool_shell,
    }
    runner = runners.get(kind)
    if not runner:
        raise ToolError(f"unknown tool {kind}")
    if kind == "shell":
        msg = runner(agent, action, sudo_password=sudo_password)
    else:
        msg = runner(agent, action)
    log("tool", msg.split("\n", 1)[0], agent.get("name", ""), agent.get("team", ""))
    if persist:
        with _lock:
            live = find(STATE["agents"], agent.get("id") or "") or agent
            prev = (live.get("lastReply") or "").rstrip()
            live["lastReply"] = (prev + "\n\n" + msg).strip() if prev else msg
            save_state(STATE)
    _notify(msg.split("\n", 1)[0], title="Done")
    return msg


def _maybe_run_tool(agent: dict, action: dict) -> None:
    action = _normalize_action(action)
    if action.get("type") not in TOOL_KINDS:
        return
    try:
        if _elevation_kind(action):
            action["needsSudo"] = True
            action["force_user"] = True
        if _needs_tool_approval(agent, action):
            result = request_permission(agent, _tool_summary(action), action)
            if result.get("auto") and result.get("approved"):
                _run_tool(agent, action)
            else:
                with _lock:
                    live = find(STATE["agents"], agent.get("id") or "") or agent
                    note = ("Proposed " + _tool_summary(action)
                            + " — waiting for review, then your approval.")
                    prev = (live.get("lastReply") or "").rstrip()
                    live["lastReply"] = (prev + "\n\n" + note).strip() if prev else note
                    save_state(STATE)
            return
        _run_tool(agent, action)
    except ToolError as exc:
        log("error", str(exc), agent.get("name", ""), agent.get("team", ""))
        with _lock:
            live = find(STATE["agents"], agent.get("id") or "") or agent
            live["lastReply"] = str(exc)
            live["status"] = "error"
            save_state(STATE)


def _tool_from_ask(action: dict) -> dict | None:
    """If an 'ask' payload already describes a write/shell, promote it."""
    if action.get("path") or action.get("file"):
        promoted = _normalize_action(action)
        if promoted.get("type") not in TOOL_KINDS:
            if action.get("command") or action.get("cmd"):
                promoted["type"] = "shell"
            elif action.get("content") is not None or action.get("contents") is not None:
                promoted["type"] = "write"
            else:
                promoted["type"] = "mkdir" if action.get("mkdir") else "write"
        if promoted.get("type") in TOOL_KINDS:
            return promoted
    if action.get("command") or action.get("cmd"):
        promoted = _normalize_action(action)
        promoted["type"] = "shell"
        return promoted
    return None


def _apply_actions(agent: dict, actions: list, hops: int) -> None:
    rules = effective_rules(agent)
    for action in actions:
        if not isinstance(action, dict):
            continue
        action = _normalize_action(action)
        kind = action.get("type") or ""
        if kind in ("none", "", "reply"):
            continue
        if kind in TOOL_KINDS:
            _maybe_run_tool(agent, action)
            continue
        if kind == "ask":
            inner = _tool_from_ask(action)
            if inner:
                _maybe_run_tool(agent, inner)
            else:
                detail = action.get("detail") or "an action"
                request_permission(agent, f"wants to {detail}", action)
        elif kind == "assign":
            if hops >= MAX_HOPS:
                log("error", "Assignment dropped (too many hops)",
                    agent.get("name", ""))
                continue
            dest = find(STATE["agents"], action.get("to") or "") \
                or find_named(STATE["agents"], action.get("to") or "")
            task = (action.get("task") or "").strip()
            if not dest or not task:
                continue
            if not can_assign(agent, dest):
                log("error",
                    f"{agent.get('name')} cannot assign to {dest.get('name')}",
                    agent.get("name", ""))
                continue
            log("assign",
                f"{agent.get('name')} → {dest.get('name')}: {task}",
                agent.get("name", ""), agent.get("team", ""))
            _work.put(("task", dest["id"],
                       f"[Assigned by {agent.get('name')}] {task}", hops + 1))
        elif kind == "message":
            _dispatch_message(agent, action.get("to") or "",
                              action.get("text") or "", hops)
        elif kind == "escalate":
            request_permission(
                agent, action.get("detail") or "escalated a decision",
                action, find_supervisor(agent))

    if "ask-before-commit" in rules and any(
            (a.get("type") or a.get("kind") or "") == "commit" for a in actions):
        request_permission(agent, "wants to commit its changes",
                           {"type": "commit"})

    if "report-to-lead" in rules:
        lead = find_supervisor(agent)
        if lead:
            log("report",
                f"{agent.get('name')} → {lead.get('name')}: "
                f"{(agent.get('lastReply') or '')[:400]}",
                agent.get("name", ""), agent.get("team", ""))


def _dispatch_message(src: dict, to_spec: str, text: str, hops: int) -> None:
    text = (text or "").strip()
    if not text or hops >= MAX_HOPS:
        return
    to_spec = (to_spec or "").strip()
    dest_agent = None
    dest_team = None
    if to_spec.startswith("team:"):
        dest_team = find(STATE["teams"], to_spec.split(":", 1)[1])
    elif to_spec in ("lead", "supervisor"):
        dest_agent = find_supervisor(src)
    else:
        dest_agent = find(STATE["agents"], to_spec) or find_named(STATE["agents"], to_spec)
        dest_team = find(STATE["teams"], to_spec) or find_named(STATE["teams"], to_spec)

    if dest_agent:
        if not can_talk(src, dest_agent):
            log("error", f"{src.get('name')} is not allowed to message "
                f"{dest_agent.get('name')}", src.get("name", ""))
            return
        log("message", f"{src.get('name')} → {dest_agent.get('name')}: {text}",
            src.get("name", ""), src.get("team", ""))
        _work.put(("task", dest_agent["id"],
                   f"[Message from {src.get('name')}] {text}", hops + 1))
        return
    if dest_team:
        if not can_talk(src, dest_team):
            log("error", f"{src.get('name')} is not allowed to message team "
                f"{dest_team.get('name')}", src.get("name", ""))
            return
        log("message", f"{src.get('name')} → team {dest_team.get('name')}: {text}",
            src.get("name", ""), dest_team.get("name", ""))
        for other in STATE["agents"]:
            if other.get("teamId") == dest_team["id"] and other["id"] != src["id"]:
                _work.put(("task", other["id"],
                           f"[Team message from {src.get('name')}] {text}",
                           hops + 1))


# ── worker ──────────────────────────────────────────────────────────────
def _direct_reports(agent: dict) -> list[dict]:
    return [a for a in STATE["agents"] if a.get("reportsTo") == agent.get("id")]


def agent_duties(agent: dict) -> list[str]:
    """User override, else infer from role text, rank, and who reports to this agent."""
    explicit = [d for d in (agent.get("duties") or []) if d in DUTIES]
    if explicit:
        return explicit
    blob = f"{agent.get('role') or ''} {agent.get('name') or ''}".lower()
    reports = _direct_reports(agent)
    rank = int(agent.get("rank") or 0)
    out: list[str] = []
    if any(tok in blob for tok in ("review", "qa", "audit", "test")):
        out.append("review")
    if any(tok in blob for tok in (
            "code", "dev", "engineer", "implement", "worker", "build", "write")):
        out.append("implement")
    if rank >= 1 or reports or any(
            tok in blob for tok in ("lead", "director", "manager", "pm", "coord")):
        out.append("coordinate")
    if "review" in out and rank == 0 and not reports:
        out = [d for d in out if d not in ("implement", "coordinate")]
    if not out:
        out.append("coordinate" if reports or rank >= 1 else "implement")
    return out


def _label(agent: dict) -> str:
    duties = ", ".join(agent_duties(agent))
    return f"{agent.get('name')} ({agent.get('role') or 'agent'}; {duties})"


def _org_tree(team: dict | None, you_id: str) -> str:
    members = [a for a in STATE["agents"]
               if not team or a.get("teamId") == team.get("id")]
    ids = {a["id"] for a in members}

    def render(agent: dict, indent: int) -> list[str]:
        mark = " ← you" if agent["id"] == you_id else ""
        lines = ["  " * indent + "- " + _label(agent) + mark]
        kids = [a for a in members if a.get("reportsTo") == agent["id"]]
        kids.sort(key=lambda a: (-int(a.get("rank") or 0), a.get("name") or ""))
        for kid in kids:
            lines.extend(render(kid, indent + 1))
        return lines

    roots = [a for a in members
             if not a.get("reportsTo") or a.get("reportsTo") not in ids]
    roots.sort(key=lambda a: (-int(a.get("rank") or 0), a.get("name") or ""))
    if not members:
        return "(no teammates yet)"
    lines: list[str] = []
    seen: set[str] = set()
    for root in roots:
        if root["id"] in seen:
            continue
        chunk = render(root, 0)
        lines.extend(chunk)
        # mark visited via names in chunk is messy; walk
        stack = [root]
        while stack:
            cur = stack.pop()
            if cur["id"] in seen:
                continue
            seen.add(cur["id"])
            stack.extend([a for a in members if a.get("reportsTo") == cur["id"]])
    for orphan in members:
        if orphan["id"] not in seen:
            lines.extend(render(orphan, 0))
            seen.add(orphan["id"])
    return "\n".join(lines) if lines else "(no teammates yet)"


def _best_report_for(agent: dict, need: str) -> dict | None:
    reports = _direct_reports(agent)
    hits = [a for a in reports if need in agent_duties(a)]
    if hits:
        return hits[0]
    if need == "implement":
        hits = [a for a in reports if "review" not in agent_duties(a)
                and int(a.get("rank") or 0) == 0]
        if hits:
            return hits[0]
    if reports:
        return reports[0]
    return None


def _role_playbook(agent: dict) -> str:
    duties = agent_duties(agent)
    reports = _direct_reports(agent)
    boss = find_reports_to(agent)
    team = team_of(agent)
    peer_rev = find_peer_reviewer(agent)
    peer_impl = find_peer_coder(agent)
    parts = [
        "Organisation (live chart — this is how work should flow):",
        _org_tree(team, agent["id"]),
        "",
        f"Your duties: {', '.join(duties)}."
        + (" (inferred from your role and the chart; override them in Org if wrong.)"
           if not (agent.get("duties") or []) else ""),
    ]
    if boss:
        parts.append(f"You report to {_label(boss)}.")
    else:
        parts.append("You report to the user.")
    if reports:
        parts.append("People who report to you: " + "; ".join(_label(a) for a in reports) + ".")
        impl = _best_report_for(agent, "implement")
        rev = _best_report_for(agent, "review")
        coord = _best_report_for(agent, "coordinate")
        parts.append(
            "You have reports, so you coordinate. Delegate; do not do their jobs. "
            "Match the task to a report's duties"
            + (f" — implementation to {impl.get('name')}" if impl else "")
            + (f", review to {rev.get('name')}" if rev and rev != impl else "")
            + (f", further coordination to {coord.get('name')}" if coord and coord not in (impl, rev) else "")
            + ". You may only assign to those direct reports."
        )
        if boss:
            parts.append(
                f"When that work is reviewed and ready, message {boss.get('name')} "
                "with the outcome. Never emit write/mkdir/shell yourself unless "
                "nobody under you can do it."
            )
    elif "review" in duties:
        coder = peer_impl
        parts.append(
            "You review. You do not implement. "
            + (f"{coder.get('name')} writes; you review their proposed files. "
               if coder else "Review whatever change is sent to you. ")
            + "APPROVE only if it matches the task; otherwise DENY with notes "
            + (f"and message {coder.get('name')} to fix it. " if coder else "")
            + (f"Approved work goes next to {boss.get('name')}." if boss else
               "Approved work goes next to the user.")
        )
    else:
        parts.append(
            "You have no reports, so you do the work yourself with write/mkdir/shell. "
            "Do not assign downward."
        )
        if peer_rev:
            parts.append(
                f"Your peer {peer_rev.get('name')} reviews. After you emit a tool "
                f"action, message them that it is ready. Do not skip them or go "
                f"straight to {boss.get('name') if boss else 'the user'}."
            )
        elif boss:
            parts.append(
                f"When you are done, message {boss.get('name')}. "
                "Writes wait for approval up the reporting line, then the user."
            )
    brief = (agent.get("brief") or "").strip()
    if brief:
        parts.append("Standing instructions from the user: " + brief)
    if team and (team.get("brief") or "").strip():
        parts.append("Team brief: " + team["brief"].strip())
    return "\n".join(parts)


def _system_prompt(agent: dict) -> str:
    rank = RANK_NAMES.get(int(agent.get("rank") or 0), "worker")
    system = (
        f"You are {agent.get('name')}, a {agent.get('role')} ({rank}) in the "
        f"Arch Shell Agent Centre on Arch Linux."
    )
    repo = agent.get("repo") or ""
    if repo:
        system += f" You are responsible for the repository at {repo}."
    team = team_of(agent)
    if team:
        system += f" You belong to team {team.get('name')}."
    supervisor = find_supervisor(agent)
    if supervisor:
        system += f" You report to {supervisor.get('name')}."
    reports = [a.get("name") for a in STATE["agents"]
               if a.get("reportsTo") == agent["id"]]
    if reports:
        system += " Agents who report to you: " + ", ".join(reports) + "."
    rules = effective_rules(agent)
    if rules:
        system += " Standing rules: " + "; ".join(rules) + "."
    comms = effective_comms(agent)
    home = str(HOME)
    workspace = repo or home
    system += "\n\n" + _role_playbook(agent)
    system += (
        f" Communication policy is '{comms}'. "
        f"Your workspace is {workspace}. Home is {home}. "
        "You cannot touch the filesystem with prose. Saying you created a file "
        "does nothing. To actually do work you MUST emit a JSON object — last "
        "thing in the reply — of the form {\"actions\":[...]} with one or more of: "
        '{"type":"write","path":"~/hello.txt","content":"hello world"} , '
        '{"type":"mkdir","path":"~/projects/foo"} , '
        '{"type":"shell","command":"ls ~"} , '
        '{"type":"read","path":"~/hello.txt"} , '
        '{"type":"assign","to":"AgentName","task":"..."} , '
        '{"type":"message","to":"AgentName|lead","text":"..."} . '
        "Paths may use ~ and must stay under the home directory or repo for "
        "write, mkdir and read. "
        "To run a command that needs root, emit "
        '{"type":"shell","command":"sudo pacman -S --noconfirm pkg"} or '
        '{"type":"shell","sudo":true,"command":"pacman -S --noconfirm pkg"}. '
        "The user will approve it and type their sudo password. Never invent, "
        "guess, or store a password. Use sudo only for system work "
        "(/etc, pacman, systemctl); do not sudo home-directory edits. "
        "pacman must use --noconfirm. "
        "Dangerous commands (wipe /, mkfs, reboot) stay blocked even with sudo. "
        "write creates parent folders. "
        "Use {\"actions\":[]} only when the user asked a question, not when they asked you to do something. "
        "Never claim success unless you emitted the correct action for your role in this reply. "
        "The desktop renders Markdown (bold, italic, headings, lists, links, code) and LaTeX "
        "($inline$ and $$blocks$$, including \\frac, \\sqrt, Greek letters and super/subscripts). "
        "Use that formatting in the prose the user reads."
    )
    return system


def run_task(agent_id: str, task: str, hops: int = 0) -> None:
    with _lock:
        agent = find(STATE["agents"], agent_id)
        if not agent:
            return
        agent["status"] = "working"
        agent["task"] = task
        save_state(STATE)

    log("task", f"Started: {task}", agent.get("name", ""), agent.get("team", ""))

    try:
        raw = call_provider(
            agent.get("provider", "openai"),
            agent.get("model") or agent.get("resolvedModel") or "",
            _system_prompt(agent),
            task,
        )
        reply, actions, had_json = _split_actions(raw)
        if (not had_json and _task_looks_like_work(task)
                and not task.startswith("[System]")):
            raw = call_provider(
                agent.get("provider", "openai"),
                agent.get("model") or agent.get("resolvedModel") or "",
                _system_prompt(agent),
                task + "\n\nSYSTEM: Your last reply had no tool JSON, so nothing "
                "was executed. Reply again. The last line MUST be "
                '{"actions":[{"type":"write","path":"...","content":"..."}]} '
                "or mkdir/shell/assign. Do not only describe the work.",
            )
            reply, actions, had_json = _split_actions(raw)
        with _lock:
            agent = find(STATE["agents"], agent_id) or agent
            agent["status"] = "idle"
            agent["lastReply"] = reply
            if _model_ok.get(canonical_provider(agent.get("provider", ""))):
                agent["resolvedModel"] = _model_ok[
                    canonical_provider(agent.get("provider", ""))]
            save_state(STATE)
        log("reply", reply, agent.get("name", ""), agent.get("team", ""))
        _apply_actions(agent, actions, hops)

    except (ProviderError, RuntimeError, KeyError, ValueError) as exc:
        with _lock:
            agent = find(STATE["agents"], agent_id) or agent
            agent["status"] = "error"
            agent["lastReply"] = str(exc)
            save_state(STATE)
        log("error", str(exc), agent.get("name", ""), agent.get("team", ""))


def run_supervise(pending_id: str) -> None:
    with _lock:
        entry = next((p for p in STATE["pending"] if p["id"] == pending_id), None)
    if not entry or entry.get("status") != "awaiting-agent":
        return
    supervisor = find(STATE["agents"], entry.get("approverId") or "")
    subject = find(STATE["agents"], entry.get("agentId") or "")
    if not supervisor:
        with _lock:
            entry["approverKind"] = "user"
            entry["approverName"] = "you"
            entry["status"] = "awaiting-user"
            save_state(STATE)
        return
    prompt = (
        f"{entry.get('agent')} wants: {entry.get('what')}.\n"
        f"Proposed action:\n{json.dumps(entry.get('payload') or {}, indent=2)}\n\n"
        "You are reviewing this before it moves up the chain. "
        "Read the path and content. Reply with exactly one of:\n"
        "APPROVE: <one-line reason>\n"
        "DENY: <one-line reason>\n"
        "ESCALATE: <one-line reason>\n"
        "Do not emit an actions JSON object. Do not implement the work yourself."
    )
    try:
        raw = call_provider(
            supervisor.get("provider", "openai"),
            supervisor.get("model") or "",
            _system_prompt(supervisor) + " You are deciding a permission request.",
            prompt,
        )
        verdict = (raw or "").strip().splitlines()[0]
        upper = verdict.upper()
        if upper.startswith("APPROVE"):
            _resolve_permission(pending_id, True, supervisor.get("name", ""),
                                verdict)
        elif upper.startswith("DENY"):
            _resolve_permission(pending_id, False, supervisor.get("name", ""),
                                verdict)
        else:
            # Bubble to the supervisor's supervisor, else the user.
            nxt = find_supervisor(supervisor)
            with _lock:
                entry = next((p for p in STATE["pending"] if p["id"] == pending_id),
                             None)
                if not entry:
                    return
                if nxt:
                    entry["approverId"] = nxt["id"]
                    entry["approverName"] = nxt.get("name", "")
                    entry["status"] = "awaiting-agent"
                else:
                    entry["approverKind"] = "user"
                    entry["approverId"] = ""
                    entry["approverName"] = "you"
                    entry["status"] = "awaiting-user"
                save_state(STATE)
            log("permission",
                f"{supervisor.get('name')} escalated {entry.get('what')}",
                supervisor.get("name", ""))
            if nxt:
                _work.put(("supervise", pending_id))
    except (ProviderError, RuntimeError, KeyError, ValueError) as exc:
        log("error", f"Supervisor {supervisor.get('name')} failed: {exc}",
            supervisor.get("name", ""))
        with _lock:
            entry = next((p for p in STATE["pending"] if p["id"] == pending_id), None)
            if entry:
                entry["approverKind"] = "user"
                entry["approverName"] = "you"
                entry["status"] = "awaiting-user"
                save_state(STATE)


def _resolve_permission(ident: str, approve: bool, by: str, note: str = "",
                        sudo_password: str = "") -> None:
    password = sudo_password if isinstance(sudo_password, str) else ""
    with _lock:
        entry = next((p for p in STATE["pending"] if p["id"] == ident), None)
        STATE["pending"] = [p for p in STATE["pending"] if p["id"] != ident]
        save_state(STATE)
    if not entry:
        return
    decision = "Approved" if approve else "Denied"
    extra = f" ({note})" if note else ""
    log("permission",
        f"{decision} by {by}: {entry.get('agent')} {entry.get('what')}{extra}",
        entry.get("agent", ""))
    payload = _public_payload(entry.get("payload") or {})
    agent = _live_agent(entry.get("agentId") or "")
    if not approve:
        denied = f"Denied by {by}: {entry.get('what')}."
        if agent and agent.get("id") == "chat":
            _append_chat_note(denied)
        elif agent:
            with _lock:
                live = find(STATE["agents"], agent["id"]) or agent
                live["lastReply"] = (
                    (live.get("lastReply") or "") + "\n\n" + denied
                ).strip()
                save_state(STATE)
        return
    payload = _normalize_action(payload)
    inner = _tool_from_ask(payload) if payload.get("type") == "ask" else None
    if inner:
        payload = inner
    if _elevation_kind(payload):
        payload["needsSudo"] = True
        payload["force_user"] = True

    # Agent approved a tool → send it up. Only the user (or auto) executes.
    if (entry.get("approverKind") == "agent"
            and payload.get("type") in TOOL_KINDS):
        approver = find(STATE["agents"], entry.get("approverId") or "")
        nxt = find_reports_to(approver) if approver else None
        what = entry.get("what") or _tool_summary(payload)
        flags = _permission_flags(payload)
        if nxt and not flags["needsSudo"]:
            new_entry = {
                "id": uuid.uuid4().hex[:8],
                "agent": entry.get("agent", ""),
                "agentId": entry.get("agentId") or "",
                "what": f"cleared by {entry.get('approverName')}: {what}",
                "payload": _public_payload(payload),
                "at": time.strftime("%H:%M:%S"),
                "approverKind": "agent",
                "approverId": nxt["id"],
                "approverName": nxt.get("name", ""),
                "status": "awaiting-agent",
                **flags,
            }
            with _lock:
                STATE["pending"].append(new_entry)
                save_state(STATE)
            log("permission",
                f"{entry.get('agent')} {what} · awaiting {nxt.get('name')}",
                entry.get("agent", ""))
            _notify(f"{nxt.get('name')} review: {what}")
            _work.put(("supervise", new_entry["id"]))
            return
        new_entry = {
            "id": uuid.uuid4().hex[:8],
            "agent": entry.get("agent", ""),
            "agentId": entry.get("agentId") or "",
            "what": f"{entry.get('approverName')} asks you to apply: {what}",
            "payload": _public_payload(payload),
            "at": time.strftime("%H:%M:%S"),
            "approverKind": "user",
            "approverId": "",
            "approverName": "you",
            "status": "awaiting-user",
            **flags,
        }
        with _lock:
            STATE["pending"].append(new_entry)
            save_state(STATE)
        log("permission",
            f"{entry.get('agent')} {what} · awaiting you",
            entry.get("agent", ""))
        _notify(new_entry["what"])
        return

    if (agent and payload.get("type") == "shell"
            and _elevation_kind(payload) == "sudo"
            and not password and not _sudo_cached()):
        entry["sudoNeedsPassword"] = True
        entry["needsSudo"] = True
        entry["elevation"] = "sudo"
        entry["approverKind"] = "user"
        entry["approverName"] = "you"
        entry["status"] = "awaiting-user"
        with _lock:
            STATE["pending"].append(entry)
            save_state(STATE)
        _notify("sudo needs your password — type it on the prompt and approve.")
        return

    if agent and payload.get("type") in TOOL_KINDS:
        persist = agent.get("id") != "chat"
        try:
            msg = _run_tool(agent, payload, persist=persist,
                            sudo_password=password)
            if not persist:
                _append_chat_note(msg)
        except ToolError as exc:
            err = _scrub_secret(str(exc), password)
            log("error", err, agent.get("name", ""))
            if agent.get("id") == "chat":
                _append_chat_note(err)
            else:
                with _lock:
                    live = find(STATE["agents"], agent["id"]) or agent
                    live["lastReply"] = err
                    live["status"] = "error"
                    save_state(STATE)
        return
    if agent and payload.get("type") in ("assign", "message"):
        _apply_actions(agent, [payload], 0)


def worker() -> None:
    while True:
        job = _work.get()
        try:
            kind = job[0]
            if kind == "task":
                hops = job[3] if len(job) > 3 else 0
                try:
                    run_task(job[1], job[2], hops)
                except Exception:
                    with _lock:
                        agent = find(STATE["agents"], job[1])
                        if agent:
                            agent["status"] = "error"
                            save_state(STATE)
                    raise
            elif kind == "supervise":
                run_supervise(job[1])
            elif kind == "message":
                src = find(STATE["agents"], job[1])
                if src:
                    _dispatch_message(src, job[2], job[3], job[4] if len(job) > 4 else 0)
        except Exception as exc:
            log("error", f"worker failure: {exc}")
        finally:
            _work.task_done()


# ── direct chat (no org / approval chain) ────────────────────────────────
def load_chat() -> dict:
    try:
        with CHAT_FILE.open(encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, dict):
            data = {}
    except (OSError, ValueError):
        data = {}
    provider = canonical_provider(data.get("provider") or "google")
    if provider not in PROVIDER_DEFAULTS:
        provider = next(iter(PROVIDER_DEFAULTS))
    messages = data.get("messages") or []
    if not isinstance(messages, list):
        messages = []
    cleaned = []
    for item in messages:
        if not isinstance(item, dict):
            continue
        role = item.get("role") or "assistant"
        if role not in ("user", "assistant"):
            role = "assistant"
        cleaned.append({
            "role": role,
            "content": str(item.get("content") or ""),
            "at": str(item.get("at") or ""),
        })
    return {
        "provider": provider,
        "model": str(data.get("model") or ""),
        "messages": cleaned,
    }


def save_chat(chat: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = CHAT_FILE.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        json.dump({
            "provider": chat.get("provider") or "google",
            "model": chat.get("model") or "",
            "messages": list(chat.get("messages") or [])[-MAX_CHAT_MESSAGES:],
        }, fh, indent=2)
    tmp.replace(CHAT_FILE)


def _chat_agent() -> dict:
    return {
        "id": "chat",
        "name": "Chat",
        "role": "Assistant",
        "repo": "",
        "rules": [],
        "approval": "auto",
        "rank": 0,
        "reportsTo": "",
        "brief": "",
        "duties": ["implement"],
        "team": "",
        "teamId": "",
    }


def _chat_system() -> str:
    return (
        f"You are a helpful desktop assistant on this Arch Linux computer. "
        f"The user's home directory is {HOME}. "
        "You can read, write and create files and run shell commands. "
        "You cannot change the filesystem with prose — emit a JSON object as "
        "the last part of your reply, for example:\n"
        '{"actions":[{"type":"write","path":"~/hello.txt","content":"hi"}]}\n'
        "Action types: write (path, content), mkdir (path), read (path), "
        "shell (command). Paths may use ~ and must stay under the home directory. "
        "For root work emit "
        '{"type":"shell","command":"sudo pacman -S --noconfirm pkg"} or '
        '{"type":"shell","sudo":true,"command":"..."}. The user approves and '
        "types their sudo password — never invent or store one. "
        "When you are only talking, end with {\"actions\":[]}. "
        "Do not claim you wrote a file or ran a command unless you emitted "
        "that action. Dangerous commands (rm -rf of /, mkfs, reboot) are blocked "
        "even with sudo. "
        "The chat panel renders Markdown (bold, italic, headings, lists, links, code) "
        "and LaTeX ($inline$ and $$blocks$$). Use that in replies to the user."
    )


def run_chat_turn(provider: str, model: str, text: str) -> dict:
    user_text = (text or "").strip()
    if not user_text:
        raise ProviderError("message required")
    at = time.strftime("%H:%M:%S")
    with _lock:
        chat = load_chat()
        if provider:
            chat["provider"] = canonical_provider(provider)
        if model is not None and str(model).strip():
            chat["model"] = str(model).strip()
        chat["messages"].append({
            "role": "user", "content": user_text, "at": at,
        })
        chat["messages"] = chat["messages"][-MAX_CHAT_MESSAGES:]
        save_chat(chat)
        history = list(chat["messages"])
        use_provider = chat["provider"]
        use_model = chat.get("model") or ""
    log("chat", f"You: {user_text[:120]}", "Chat", "")

    transcript = []
    for item in history[-24:]:
        who = "User" if item.get("role") == "user" else "Assistant"
        transcript.append(f"{who}: {item.get('content') or ''}")
    prompt = "\n\n".join(transcript)

    notes: list[str] = []
    reply = ""
    agent = _chat_agent()
    try:
        for _ in range(3):
            raw = call_provider(use_provider, use_model, _chat_system(), prompt)
            reply, actions, _had = _split_actions(raw)
            tool_bits: list[str] = []
            waiting_sudo = False
            for action in actions:
                if not isinstance(action, dict):
                    continue
                action = _normalize_action(action)
                if action.get("type") not in TOOL_KINDS:
                    continue
                if _elevation_kind(action):
                    action["needsSudo"] = True
                    action["force_user"] = True
                    cmd = (action.get("command") or action.get("cmd") or "").strip()
                    request_permission(agent, _tool_summary(action), action)
                    tool_bits.append(
                        f"Waiting for you to approve `{cmd}` and enter your "
                        "sudo password. It is used once and not saved."
                    )
                    waiting_sudo = True
                    continue
                try:
                    tool_bits.append(_run_tool(agent, action, persist=False))
                except ToolError as exc:
                    tool_bits.append(str(exc))
            if not tool_bits or waiting_sudo:
                break
            notes.extend(tool_bits)
            prompt = (
                prompt
                + "\n\nAssistant: " + (reply or raw or "")
                + "\n\nSYSTEM (tool results):\n"
                + "\n".join(tool_bits)
                + "\n\nContinue. If finished, reply to the user and emit "
                "{\"actions\":[]}."
            )
    except ProviderError as exc:
        with _lock:
            chat = load_chat()
            chat["messages"].append({
                "role": "assistant",
                "content": f"The model request failed: {exc}",
                "at": time.strftime("%H:%M:%S"),
            })
            chat["messages"] = chat["messages"][-MAX_CHAT_MESSAGES:]
            save_chat(chat)
        raise

    visible = (reply or "").strip()
    if notes:
        visible = (visible + ("\n\n" if visible else "") + "\n".join(notes)).strip()
    if not visible:
        visible = "Done."
    with _lock:
        chat = load_chat()
        chat["messages"].append({
            "role": "assistant",
            "content": visible,
            "at": time.strftime("%H:%M:%S"),
        })
        chat["messages"] = chat["messages"][-MAX_CHAT_MESSAGES:]
        save_chat(chat)
        return {
            "ok": True,
            "reply": visible,
            "messages": chat["messages"],
            "provider": chat["provider"],
            "model": chat.get("model") or "",
        }


# ── HTTP ────────────────────────────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _send(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode())
        except ValueError:
            return {}

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path, qs = parsed.path, urllib.parse.parse_qs(parsed.query)
        if path == "/health":
            return self._send({"ok": True, "port": PORT})
        if path == "/models":
            provider = (qs.get("provider") or ["openai"])[0]
            return self._send({
                "ok": True,
                "provider": canonical_provider(provider),
                "models": list_provider_models(provider),
            })
        if path == "/state":
            with _lock:
                stored = load_providers()
                dirty = False
                for name in list(PROVIDER_DEFAULTS):
                    rec = take_finished_login(name)
                    if rec:
                        stored[name] = rec
                        dirty = True
                        log("provider",
                            f"{PROVIDER_DEFAULTS[name]['label']} signed in"
                            + (f" as {rec.get('account')}" if rec.get("account") else ""))
                if dirty:
                    save_providers(stored)
                providers = {
                    name: public_provider(name, stored.get(name), _model_ok.get(name, ""))
                    for name in PROVIDER_DEFAULTS
                }
                return self._send({
                    "ok": True,
                    "teams": STATE["teams"],
                    "agents": [
                        {**a, "resolvedDuties": agent_duties(a)}
                        for a in STATE["agents"]
                    ],
                    "activity": STATE["activity"][:60],
                    "pending": STATE["pending"],
                    "providers": providers,
                    "knownProviders": {
                        n: {"label": c["label"], "model": c["model"],
                            "fallbacks": peek_models(n, stored.get(n)) or c["fallbacks"],
                            "supportsLogin": bool(c.get("supportsLogin")),
                            "keyHint": c.get("keyHint") or "",
                            "loginHint": c.get("loginHint") or ""}
                        for n, c in PROVIDER_DEFAULTS.items()
                    },
                    "providerOrder": list(PROVIDER_DEFAULTS),
                    "rulePresets": RULE_PRESETS,
                    "dutyPresets": list(DUTIES),
                    "ranks": RANK_NAMES,
                    "approvalModes": list(APPROVAL_MODES),
                    "commsModes": list(COMMS_MODES),
                })
        if path == "/chat":
            with _lock:
                chat = load_chat()
            return self._send({"ok": True, **chat})
        return self._send({"error": "not found"}, 404)

    def do_POST(self):
        body = self._body()
        path = self.path

        if path == "/teams":
            name = (body.get("name") or "").strip()
            if not name:
                return self._send({"error": "name required"}, 400)
            team = _norm_team({
                "name": name,
                "parentId": body.get("parentId") or "",
                "rules": body.get("rules") or [],
                "approval": body.get("approval") or "higher",
                "comms": body.get("comms") or "team",
            })
            with _lock:
                STATE["teams"].append(team)
                save_state(STATE)
            log("team", f"Team created: {name}")
            return self._send({"ok": True, "team": team})

        if path == "/teams/update":
            ident = body.get("id")
            with _lock:
                team = find(STATE["teams"], ident)
                if not team:
                    return self._send({"error": "unknown team"}, 404)
                if body.get("parentId") == ident:
                    return self._send({"error": "a team cannot parent itself"}, 400)
                merged = dict(team)
                for key in ("name", "parentId", "leadAgentId", "rules",
                            "approval", "comms", "brief"):
                    if key in body and body[key] is not None:
                        merged[key] = body[key]
                merged["id"] = ident
                team.clear()
                team.update(_norm_team(merged))
                team["id"] = ident
                save_state(STATE)
            return self._send({"ok": True, "team": team})

        if path == "/teams/delete":
            ident = body.get("id")
            with _lock:
                STATE["teams"] = [t for t in STATE["teams"] if t["id"] != ident]
                for t in STATE["teams"]:
                    if t.get("parentId") == ident:
                        t["parentId"] = ""
                STATE["agents"] = [a for a in STATE["agents"] if a.get("teamId") != ident]
                save_state(STATE)
            return self._send({"ok": True})

        if path == "/agents":
            team = find(STATE["teams"], body.get("team", ""))
            agent = _norm_agent({
                "name": body.get("name") or "Agent",
                "role": body.get("role") or "Developer",
                "repo": body.get("repo") or "",
                "provider": body.get("provider") or "openai",
                "model": body.get("model") or "",
                "teamId": team["id"] if team else "",
                "team": team["name"] if team else "",
                "rank": body.get("rank", 0),
                "reportsTo": body.get("reportsTo") or "",
                "rules": body.get("rules") if "rules" in body
                         else (list(team.get("rules") or ["ask-before-commit"])
                               if team else ["ask-before-commit"]),
                "approval": body.get("approval") or "inherit",
                "brief": body.get("brief") or "",
                "duties": body.get("duties") or [],
            })
            with _lock:
                if team and not agent.get("reportsTo"):
                    if agent["rank"] == 0 and team.get("leadAgentId"):
                        agent["reportsTo"] = team["leadAgentId"]
                    elif agent["rank"] == 1:
                        directors = [
                            a for a in STATE["agents"]
                            if a.get("teamId") == team["id"]
                            and int(a.get("rank") or 0) >= 2
                        ]
                        if directors:
                            agent["reportsTo"] = directors[0]["id"]
                STATE["agents"].append(agent)
                if team and not team.get("leadAgentId") and agent["rank"] >= 1:
                    team["leadAgentId"] = agent["id"]
                save_state(STATE)
            log("agent", f"Agent added: {agent['name']} ({agent['role']})",
                agent["name"], agent["team"])
            return self._send({"ok": True, "agent": agent})

        if path == "/agents/update":
            ident = body.get("id")
            with _lock:
                agent = find(STATE["agents"], ident)
                if not agent:
                    return self._send({"error": "unknown agent"}, 404)
                for key in ("name", "role", "repo", "provider", "model",
                            "rank", "reportsTo", "rules", "approval",
                            "brief", "duties"):
                    if key in body and body[key] is not None:
                        agent[key] = body[key]
                if body.get("reportsTo") == ident:
                    agent["reportsTo"] = ""
                if "team" in body:
                    team = find(STATE["teams"], body.get("team") or "")
                    agent["teamId"] = team["id"] if team else agent.get("teamId", "")
                    agent["team"] = team["name"] if team else agent.get("team", "")
                merged = _norm_agent(agent)
                merged["id"] = ident
                agent.clear()
                agent.update(merged)
                save_state(STATE)
            return self._send({"ok": True, "agent": agent})

        if path == "/agents/delete":
            ident = body.get("id")
            with _lock:
                STATE["agents"] = [a for a in STATE["agents"] if a["id"] != ident]
                for a in STATE["agents"]:
                    if a.get("reportsTo") == ident:
                        a["reportsTo"] = ""
                for t in STATE["teams"]:
                    if t.get("leadAgentId") == ident:
                        t["leadAgentId"] = ""
                STATE["pending"] = [p for p in STATE["pending"]
                                    if p.get("agentId") != ident]
                save_state(STATE)
            return self._send({"ok": True})

        if path == "/agents/task":
            ident = body.get("id")
            task = (body.get("task") or "").strip()
            if not find(STATE["agents"], ident):
                return self._send({"error": "unknown agent"}, 404)
            if not task:
                return self._send({"error": "task required"}, 400)
            _work.put(("task", ident, task, 0))
            return self._send({"ok": True, "queued": True})

        if path == "/agents/message":
            src = find(STATE["agents"], body.get("from") or "")
            to_spec = (body.get("to") or "").strip()
            text = (body.get("text") or "").strip()
            if not src:
                return self._send({"error": "unknown sender"}, 404)
            if not to_spec or not text:
                return self._send({"error": "to and text required"}, 400)
            _work.put(("message", src["id"], to_spec, text, 0))
            return self._send({"ok": True})

        if path == "/providers":
            name = canonical_provider(body.get("name") or "")
            key = (body.get("key") or "").strip()
            if name not in PROVIDER_DEFAULTS:
                return self._send({"error": "unknown provider"}, 400)
            if name != "ollama" and not key:
                return self._send({"error": "key required"}, 400)
            providers = load_providers()
            rec = dict(providers.get(name) or {})
            rec["key"] = key
            rec["mode"] = "key" if key else "local"
            rec.pop("via", None)
            providers[name] = rec
            save_providers(providers)
            _model_ok.pop(name, None)
            log("provider", f"{PROVIDER_DEFAULTS[name]['label']} API key saved")
            return self._send({"ok": True})

        if path == "/providers/login":
            name = canonical_provider(body.get("name") or "")
            action = (body.get("action") or "start").strip().lower()
            if name not in PROVIDER_DEFAULTS:
                return self._send({"error": "unknown provider"}, 400)
            if not PROVIDER_DEFAULTS[name].get("supportsLogin"):
                return self._send({"error": "this provider only accepts an API key"}, 400)
            if action == "cancel":
                cancel_login(name)
                return self._send({"ok": True})
            try:
                if action == "import":
                    rec = import_existing(name)
                    providers = load_providers()
                    providers[name] = rec
                    save_providers(providers)
                    _model_ok.pop(name, None)
                    log("provider",
                        f"{PROVIDER_DEFAULTS[name]['label']} using existing login"
                        + (f" ({rec.get('account')})" if rec.get("account") else ""))
                    return self._send({"ok": True, "account": rec.get("account") or ""})
                result = start_login(name)
            except ProviderError as exc:
                return self._send({"error": str(exc)}, 400)
            log("provider", f"{PROVIDER_DEFAULTS[name]['label']} sign-in started")
            return self._send(result)

        if path == "/providers/delete":
            name = canonical_provider(body.get("name") or "")
            providers = load_providers()
            providers.pop(name, None)
            save_providers(providers)
            cancel_login(name)
            _model_ok.pop(name, None)
            return self._send({"ok": True})

        if path == "/permissions/resolve":
            ident = body.get("id")
            approve = bool(body.get("approve"))
            sudo_password = body.get("sudoPassword") or body.get("sudo_password") or ""
            if not isinstance(sudo_password, str):
                sudo_password = ""
            _resolve_permission(ident, approve, "you",
                                sudo_password=sudo_password)
            return self._send({"ok": True})

        if path == "/activity/clear":
            with _lock:
                STATE["activity"] = []
                save_state(STATE)
            return self._send({"ok": True})

        if path == "/chat/setup":
            with _lock:
                chat = load_chat()
                if body.get("provider"):
                    chat["provider"] = canonical_provider(body.get("provider") or "")
                    if chat["provider"] not in PROVIDER_DEFAULTS:
                        return self._send({"error": "unknown provider"}, 400)
                if "model" in body and body.get("model") is not None:
                    chat["model"] = str(body.get("model") or "").strip()
                save_chat(chat)
            return self._send({
                "ok": True,
                "provider": chat["provider"],
                "model": chat.get("model") or "",
            })

        if path == "/chat/clear":
            with _lock:
                chat = load_chat()
                chat["messages"] = []
                save_chat(chat)
            return self._send({"ok": True, "messages": []})

        if path == "/chat/send":
            try:
                result = run_chat_turn(
                    body.get("provider") or "",
                    body.get("model") if "model" in body else "",
                    body.get("text") or "",
                )
            except ProviderError as exc:
                return self._send({"error": str(exc)}, 400)
            return self._send(result)

        return self._send({"error": "not found"}, 404)


def main() -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    threading.Thread(target=worker, daemon=True).start()

    def _warm_models() -> None:
        stored = load_providers()
        for name in PROVIDER_DEFAULTS:
            try:
                list_models(name, stored.get(name) or {})
            except Exception:
                pass

    threading.Thread(target=_warm_models, daemon=True).start()
    log("daemon", f"arch-agentd listening on {HOST}:{PORT}")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
