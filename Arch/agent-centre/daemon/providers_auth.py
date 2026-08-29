"""Provider catalogue, API-key callers, and official subscription logins.

Login uses each vendor's own CLI so usage stays on that account's plan:
  Google AI Pro / Ultra  → Antigravity CLI (`agy`)
  ChatGPT Plus / Pro     → Codex CLI (`codex login`)
  Claude Pro / Max       → Claude Code (`claude`)
  GitHub Copilot         → `gh auth login`, then the Copilot editor API
"""

from __future__ import annotations

import json
import os
import re
import shutil
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HOME = Path.home()

def _extend_path() -> None:
    extras = [str(HOME / ".local" / "bin"), "/usr/local/bin"]
    parts = os.environ.get("PATH", "/usr/bin").split(":")
    for extra in extras:
        if extra not in parts:
            parts.insert(0, extra)
    os.environ["PATH"] = ":".join(parts)


_extend_path()

PROVIDER_DEFAULTS = {
    "openai": {
        "label": "OpenAI / ChatGPT",
        "model": "gpt-4o-mini",
        "fallbacks": ["gpt-4o-mini", "gpt-4.1-mini", "gpt-4o", "gpt-4.1"],
        "supportsLogin": True,
        "keyHint": "sk-… from platform.openai.com",
        "loginHint": "Sign in with ChatGPT Plus/Pro via Codex CLI (codex login).",
    },
    "anthropic": {
        "label": "Anthropic / Claude",
        "model": "claude-sonnet-4-20250514",
        "fallbacks": [
            "claude-sonnet-4-6",
            "claude-opus-4-6-thinking",
            "claude-sonnet-4-20250514",
            "claude-sonnet-4-5-20250929",
        ],
        "supportsLogin": True,
        "keyHint": "sk-ant-… from console.anthropic.com",
        "loginHint": "Sign in with Claude Pro/Max via Claude Code.",
    },
    "google": {
        "label": "Google Gemini",
        "model": "gemini-3.7-flash-high",
        "fallbacks": [
            "gemini-3.7-flash-high",
            "gemini-3.6-flash",
            "gemini-3.5-flash",
            "gemini-3.1-pro-high",
            "gemini-2.5-flash",
        ],
        "aliases": ["gemini"],
        "supportsLogin": True,
        "keyHint": "AI Studio key from aistudio.google.com/apikey",
        "loginHint": "Sign in with Google AI Pro / Ultra via Antigravity CLI (agy).",
    },
    "copilot": {
        "label": "GitHub Copilot",
        "model": "gpt-4o",
        "fallbacks": ["gpt-4o", "gpt-4.1", "claude-sonnet-4", "gemini-2.5-pro"],
        "supportsLogin": True,
        "keyHint": "GitHub token (gho_ / github_pat_) with Copilot access",
        "loginHint": "Sign in with GitHub. Uses your Copilot subscription.",
    },
    "xai": {
        "label": "xAI Grok",
        "model": "grok-3-mini",
        "fallbacks": ["grok-3-mini", "grok-3", "grok-2-latest"],
        "supportsLogin": False,
        "keyHint": "xAI API key from console.x.ai",
        "compat": "https://api.x.ai/v1/chat/completions",
    },
    "deepseek": {
        "label": "DeepSeek",
        "model": "deepseek-chat",
        "fallbacks": ["deepseek-chat", "deepseek-reasoner"],
        "supportsLogin": False,
        "keyHint": "DeepSeek key from platform.deepseek.com",
        "compat": "https://api.deepseek.com/chat/completions",
    },
    "mistral": {
        "label": "Mistral",
        "model": "mistral-small-latest",
        "fallbacks": ["mistral-small-latest", "mistral-large-latest"],
        "supportsLogin": False,
        "keyHint": "Mistral key from console.mistral.ai",
        "compat": "https://api.mistral.ai/v1/chat/completions",
    },
    "groq": {
        "label": "Groq",
        "model": "llama-3.3-70b-versatile",
        "fallbacks": ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"],
        "supportsLogin": False,
        "keyHint": "Groq key from console.groq.com",
        "compat": "https://api.groq.com/openai/v1/chat/completions",
    },
    "openrouter": {
        "label": "OpenRouter",
        "model": "openai/gpt-4o-mini",
        "fallbacks": [
            "openai/gpt-4o-mini",
            "anthropic/claude-sonnet-4",
            "google/gemini-2.5-flash",
        ],
        "supportsLogin": False,
        "keyHint": "sk-or-… from openrouter.ai/keys",
        "compat": "https://openrouter.ai/api/v1/chat/completions",
    },
    "ollama": {
        "label": "Ollama (local)",
        "model": "llama3.2",
        "fallbacks": ["llama3.2", "llama3.1", "mistral", "qwen2.5"],
        "supportsLogin": False,
        "keyHint": "Optional. Leave blank if Ollama is on this machine.",
        "compat": "http://127.0.0.1:11434/v1/chat/completions",
        "optionalKey": True,
    },
}

PROVIDER_ALIASES = {
    alias: name
    for name, cfg in PROVIDER_DEFAULTS.items()
    for alias in [name] + list(cfg.get("aliases") or [])
}

RETIRED_MODELS = {
    "openai": {"gpt-3.5-turbo-0301", "gpt-4-0314"},
    "anthropic": {"claude-3-sonnet-20240229", "claude-3-opus-20240229"},
    "google": {
        "gemini-1.5-flash", "gemini-1.5-pro", "gemini-1.5-flash-latest",
        "gemini-1.5-pro-latest",
    },
}

GOOGLE_FAST = "gemini-3.6-flash"

_login_jobs: dict[str, dict] = {}
_login_lock = threading.Lock()
_copilot_session: dict = {}
_probe_cache: dict[str, tuple[float, dict]] = {}
_model_cache: dict[str, tuple[float, list[str]]] = {}
_model_lock = threading.Lock()
MODEL_CACHE_SECS = 300


class ProviderError(RuntimeError):
    def __init__(self, message: str, status: int = 0, body: str = ""):
        super().__init__(message)
        self.status = status
        self.body = body


def canonical_provider(name: str) -> str:
    key = (name or "").strip().lower()
    if key in PROVIDER_ALIASES:
        return PROVIDER_ALIASES[key]
    if key in PROVIDER_DEFAULTS:
        return key
    return "openai"


def _which(*names: str) -> str:
    for name in names:
        path = shutil.which(name)
        if path:
            return path
    return ""


def _run(argv: list[str], timeout: int = 90, env: dict | None = None) -> str:
    try:
        proc = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
            check=False,
        )
    except FileNotFoundError as exc:
        raise ProviderError(f"not installed: {argv[0]}") from exc
    except subprocess.TimeoutExpired as exc:
        raise ProviderError("timed out talking to the signed-in CLI", status=408) from exc
    out = (proc.stdout or "").strip()
    err = (proc.stderr or "").strip()
    if proc.returncode != 0:
        raise ProviderError(err or out or f"{argv[0]} exited {proc.returncode}")
    return out


def _extract_api_error(body: str) -> str:
    if not body:
        return ""
    try:
        data = json.loads(body)
    except ValueError:
        return body[:240]
    err = data.get("error")
    if isinstance(err, dict):
        return str(err.get("message") or err.get("status") or err)[:240]
    if isinstance(err, str):
        return err[:240]
    return body[:240]


def http_json(method: str, url: str, payload: dict | None, headers: dict,
              timeout: int = 30) -> dict:
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, method=method)
    if payload is not None:
        req.add_header("Content-Type", "application/json")
    for key, value in headers.items():
        if value:
            req.add_header(key, value)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        body = ""
        try:
            body = exc.read().decode()[:800]
        except Exception:
            pass
        detail = _extract_api_error(body) or (exc.reason or "error")
        raise ProviderError(
            f"HTTP {exc.code} {detail}", status=exc.code, body=body) from exc
    except (TimeoutError, socket.timeout) as exc:
        raise ProviderError("timed out talking to the API", status=408) from exc
    except urllib.error.URLError as exc:
        reason = exc.reason
        if isinstance(reason, (TimeoutError, socket.timeout)) or (
                "timed out" in str(reason).lower()):
            raise ProviderError(
                "timed out talking to the API", status=408) from exc
        raise ProviderError(f"network error: {reason}") from exc


def record_configured(rec: dict | None, name: str = "") -> bool:
    rec = rec or {}
    if rec.get("mode") == "login":
        return True
    if (rec.get("key") or "").strip():
        return True
    if name == "ollama":
        return True
    return False


def public_provider(name: str, rec: dict | None, model_ok: str = "") -> dict:
    cfg = PROVIDER_DEFAULTS[name]
    rec = rec or {}
    mode = rec.get("mode") or ("key" if rec.get("key") else "none")
    if name == "ollama" and mode == "none":
        mode = "local"
    job = login_status(name)
    return {
        "label": cfg["label"],
        "configured": record_configured(rec, name),
        "mode": mode,
        "account": rec.get("account") or "",
        "via": rec.get("via") or "",
        "model": model_ok or cfg["model"],
        "fallbacks": cfg["fallbacks"],
        "models": peek_models(name, rec) or list(cfg["fallbacks"]),
        "supportsLogin": bool(cfg.get("supportsLogin")),
        "optionalKey": bool(cfg.get("optionalKey")),
        "keyHint": cfg.get("keyHint") or "Paste API key",
        "loginHint": cfg.get("loginHint") or "",
        "cli": probe_cli(name),
        "loginJob": job,
    }


# ── CLI / existing-session probes ───────────────────────────────────────
def probe_cli(name: str) -> dict:
    cached = _probe_cache.get(name)
    if cached and cached[0] > time.time():
        return cached[1]
    result = _probe_cli(name)
    _probe_cache[name] = (time.time() + 30, result)
    return result


def _probe_cli(name: str) -> dict:
    if name == "google":
        agy = _which("agy", "antigravity")
        gcloud = _which("gcloud")
        return {
            "available": bool(agy or gcloud),
            "tool": "agy" if agy else ("gcloud" if gcloud else ""),
            "account": "",
        }
    if name == "openai":
        auth = HOME / ".codex" / "auth.json"
        signed = auth.is_file()
        return {
            "available": bool(_which("codex") or signed),
            "tool": "codex",
            "account": "ChatGPT (Codex)" if signed else "",
        }
    if name == "anthropic":
        claude = _which("claude")
        creds = (HOME / ".claude" / ".credentials.json").is_file() or (
            HOME / ".claude.json").is_file()
        return {
            "available": bool(claude or creds),
            "tool": "claude",
            "account": "Claude Code" if creds else "",
        }
    if name == "copilot":
        token = _gh_token()
        return {
            "available": bool(_which("gh", "copilot") or token),
            "tool": "gh" if _which("gh") else ("copilot" if _which("copilot") else ""),
            "account": _gh_account() if token else "",
        }
    return {"available": False, "tool": "", "account": ""}


def _gh_token() -> str:
    gh = _which("gh")
    if not gh:
        return ""
    try:
        out = _run([gh, "auth", "token"], timeout=8)
        return out.splitlines()[0].strip()
    except ProviderError:
        return ""


def _gh_account() -> str:
    gh = _which("gh")
    if not gh:
        return ""
    try:
        return _run([gh, "api", "user", "--jq", ".login"], timeout=8)
    except ProviderError:
        return "GitHub"


def _drop_probe(name: str = "") -> None:
    if name:
        _probe_cache.pop(name, None)
        with _model_lock:
            drop = [k for k in _model_cache if k.startswith(name + ":")]
            for k in drop:
                _model_cache.pop(k, None)
    else:
        _probe_cache.clear()
        with _model_lock:
            _model_cache.clear()


def import_existing(name: str) -> dict:
    """Attach an already-signed-in vendor CLI / gh session."""
    name = canonical_provider(name)
    _drop_probe(name)
    probe = probe_cli(name)
    if name == "google":
        if _which("agy", "antigravity"):
            return {"mode": "login", "via": "agy", "account": "Google (Antigravity)"}
        if _which("gcloud"):
            try:
                _run(["gcloud", "auth", "application-default", "print-access-token"],
                     timeout=10)
            except ProviderError as exc:
                raise ProviderError(
                    "gcloud is installed but not signed in. Click Sign in.") from exc
            return {"mode": "login", "via": "gcloud", "account": "Google Cloud"}
        raise ProviderError(
            "Install Antigravity CLI (agy) to use Google AI Pro, or paste an AI Studio key.")
    if name == "openai":
        if not (HOME / ".codex" / "auth.json").is_file() and not _which("codex"):
            raise ProviderError("Install Codex CLI, then Sign in with ChatGPT.")
        if not (HOME / ".codex" / "auth.json").is_file():
            raise ProviderError("No Codex session yet. Click Sign in with ChatGPT.")
        return {"mode": "login", "via": "codex", "account": "ChatGPT"}
    if name == "anthropic":
        if not _which("claude"):
            raise ProviderError("Install Claude Code, then Sign in with Claude.")
        creds = (HOME / ".claude" / ".credentials.json").is_file() or (
            HOME / ".claude.json").is_file()
        if not creds:
            raise ProviderError("No Claude Code session yet. Click Sign in.")
        return {"mode": "login", "via": "claude", "account": "Claude"}
    if name == "copilot":
        token = _gh_token()
        if not token:
            raise ProviderError("GitHub CLI is not signed in. Click Sign in.")
        return {
            "mode": "login",
            "via": "gh",
            "account": _gh_account() or "GitHub",
            "key": token,
        }
    raise ProviderError(f"{name} does not support sign-in")


def _open_login_terminal(argv: list[str]) -> None:
    quoted = subprocess.list2cmdline(argv)
    script = (
        f"{quoted}; echo; echo 'You can close this window.'; "
        "read -r _ || true"
    )
    candidates = [
        ["kitty", "--hold", "-e", "bash", "-lc", script],
        ["xdg-terminal-exec", "bash", "-lc", script],
        ["alacritty", "-e", "bash", "-lc", script],
        ["foot", "bash", "-lc", script],
        ["xterm", "-hold", "-e", "bash", "-lc", script],
    ]
    for cmd in candidates:
        if _which(cmd[0]):
            subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            return
    subprocess.Popen(
        argv,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def login_argv(name: str) -> list[str]:
    if name == "google":
        agy = _which("agy", "antigravity")
        if agy:
            return [agy]
        gcloud = _which("gcloud")
        if gcloud:
            return [gcloud, "auth", "application-default", "login"]
        raise ProviderError(
            "Install Antigravity CLI (agy) for Google AI Pro: "
            "https://www.antigravity.google/docs/cli/install/ "
            "Or paste an AI Studio API key.")
    if name == "openai":
        codex = _which("codex")
        if not codex:
            raise ProviderError(
                "Install Codex CLI, then Sign in with ChatGPT. "
                "https://developers.openai.com/codex/cli")
        return [codex, "login"]
    if name == "anthropic":
        claude = _which("claude")
        if not claude:
            raise ProviderError(
                "Install Claude Code, then Sign in with Claude Pro/Max. "
                "https://code.claude.com/docs/en/authentication")
        return [claude]
    if name == "copilot":
        gh = _which("gh")
        if not gh:
            raise ProviderError(
                "Install GitHub CLI (pacman -S github-cli), then Sign in.")
        return [gh, "auth", "login", "-h", "github.com", "-p", "https", "-w"]
    raise ProviderError(f"{name} does not support sign-in")


def start_login(name: str) -> dict:
    name = canonical_provider(name)
    argv = login_argv(name)
    with _login_lock:
        _login_jobs[name] = {
            "status": "running",
            "message": "Complete sign-in in the window that opened.",
            "tool": argv[0],
        }
    _open_login_terminal(argv)

    def _watch() -> None:
        deadline = time.time() + 8 * 60
        while time.time() < deadline:
            time.sleep(3)
            try:
                rec = import_existing(name)
            except ProviderError:
                continue
            with _login_lock:
                _login_jobs[name] = {
                    "status": "done",
                    "message": f"Signed in as {rec.get('account') or name}",
                    "record": rec,
                }
            return
        with _login_lock:
            cur = _login_jobs.get(name) or {}
            if cur.get("status") == "running":
                _login_jobs[name] = {
                    "status": "error",
                    "message": "Sign-in timed out. Try again, or paste an API key.",
                }

    threading.Thread(target=_watch, daemon=True).start()
    _drop_probe(name)
    return {"ok": True, "status": "running",
            "message": "Complete sign-in in the window that opened."}


def take_finished_login(name: str) -> dict | None:
    with _login_lock:
        job = _login_jobs.get(name) or {}
        if job.get("status") == "done" and job.get("record"):
            rec = job["record"]
            job.pop("record", None)
            return rec
    return None


def login_status(name: str) -> dict:
    with _login_lock:
        job = dict(_login_jobs.get(name) or {})
    job.pop("record", None)
    return job


def cancel_login(name: str) -> None:
    with _login_lock:
        _login_jobs[name] = {"status": "idle", "message": ""}
    _drop_probe(name)


# ── generation ──────────────────────────────────────────────────────────
def _openai(key: str, model: str, system: str, prompt: str) -> str:
    data = http_json("POST", "https://api.openai.com/v1/chat/completions", {
        "model": model,
        "max_tokens": 2048,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
    }, {"Authorization": f"Bearer {key}"})
    return data["choices"][0]["message"]["content"].strip()


def _anthropic(key: str, model: str, system: str, prompt: str) -> str:
    data = http_json("POST", "https://api.anthropic.com/v1/messages", {
        "model": model,
        "max_tokens": 2048,
        "system": system,
        "messages": [{"role": "user", "content": prompt}],
    }, {"x-api-key": key, "anthropic-version": "2023-06-01"})
    return "".join(
        block.get("text", "") for block in data.get("content", [])
    ).strip()


def _google(key: str, model: str, system: str, prompt: str,
            bearer: str = "") -> str:
    model = _google_api_id(model)
    headers = {}
    if bearer:
        url = (f"https://generativelanguage.googleapis.com/v1beta/models/"
               f"{urllib.parse.quote(model, safe='-._')}:generateContent")
        headers["Authorization"] = f"Bearer {bearer}"
    else:
        query = urllib.parse.urlencode({"key": key})
        url = (f"https://generativelanguage.googleapis.com/v1beta/models/"
               f"{urllib.parse.quote(model, safe='-._')}:generateContent?{query}")
    gen = {"maxOutputTokens": 2048, "temperature": 0.5}
    contents = [{"role": "user", "parts": [{"text": prompt}]}]
    system_body = {
        "systemInstruction": {"parts": [{"text": system}]},
        "contents": contents,
        "generationConfig": {**gen, "thinkingConfig": {"thinkingBudget": 0}},
    }
    try:
        data = http_json("POST", url, system_body, headers)
    except ProviderError as exc:
        blob = f"{exc} {exc.body}".lower()
        thinking_unsupported = exc.status == 400 and any(
            tok in blob for tok in (
                "thinkingconfig", "thinking_config", "thinkingbudget",
                "unknown name", "unknown field",
            ))
        if not thinking_unsupported:
            raise
        data = http_json("POST", url, {
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": contents,
            "generationConfig": gen,
        }, headers)
    parts = data["candidates"][0]["content"]["parts"]
    return "".join(p.get("text", "") for p in parts).strip()


def _compat(url: str, key: str, model: str, system: str, prompt: str,
            extra_headers: dict | None = None) -> str:
    headers = {"Authorization": f"Bearer {key}"} if key else {}
    if extra_headers:
        headers.update(extra_headers)
    data = http_json("POST", url, {
        "model": model,
        "max_tokens": 2048,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
    }, headers)
    return data["choices"][0]["message"]["content"].strip()


def _copilot_token(github_token: str) -> str:
    cached = _copilot_session
    if cached.get("token") and cached.get("expires", 0) > time.time() + 60:
        return cached["token"]
    data = http_json(
        "GET",
        "https://api.github.com/copilot_internal/v2/token",
        None,
        {
            "Authorization": f"Bearer {github_token}",
            "Accept": "application/json",
            "Editor-Version": "vscode/1.96.0",
            "Editor-Plugin-Version": "copilot/1.270.0",
            "User-Agent": "GitHubCopilot/1.270.0",
        },
        timeout=20,
    )
    token = data.get("token") or ""
    if not token:
        raise ProviderError("GitHub did not return a Copilot session. Is Copilot enabled on this account?")
    expires = int(data.get("expires_at") or 0)
    if expires < 1_000_000_000:
        expires = int(time.time()) + max(expires, 600)
    _copilot_session.clear()
    _copilot_session.update({"token": token, "expires": expires})
    return token


def _copilot(github_token: str, model: str, system: str, prompt: str) -> str:
    session = _copilot_token(github_token)
    data = http_json("POST", "https://api.githubcopilot.com/chat/completions", {
        "model": model,
        "max_tokens": 2048,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
        "stream": False,
    }, {
        "Authorization": f"Bearer {session}",
        "Content-Type": "application/json",
        "Editor-Version": "vscode/1.96.0",
        "Editor-Plugin-Version": "copilot/1.270.0",
        "Copilot-Integration-Id": "vscode-chat",
        "OpenAI-Intent": "conversation-panel",
    })
    return data["choices"][0]["message"]["content"].strip()


def _cli_prompt(system: str, prompt: str) -> str:
    return (
        "Reply with the answer only. Do not run tools, edit files, or execute commands.\n\n"
        f"{system}\n\n{prompt}"
    )


def _via_cli(via: str, model: str, system: str, prompt: str) -> str:
    text = _cli_prompt(system, prompt)
    if via == "agy":
        agy = _which("agy", "antigravity")
        argv = [agy, "-p", text, "--output-format", "text"]
        if model:
            argv.extend(["--model", model])
        return _run(argv, timeout=90)
    if via == "codex":
        codex = _which("codex")
        argv = [codex, "exec", "--skip-git-repo-check", "-q", text]
        if model:
            argv.extend(["-m", model])
        return _run(argv, timeout=90)
    if via == "claude":
        claude = _which("claude")
        return _run(
            [claude, "-p", text, "--output-format", "text"],
            timeout=90,
        )
    if via == "gcloud":
        token = _run(
            ["gcloud", "auth", "application-default", "print-access-token"],
            timeout=15,
        ).splitlines()[0]
        return _google("", model or GOOGLE_FAST, system, prompt, bearer=token)
    raise ProviderError(f"unknown login backend {via}")


def _google_api_id(name: str) -> str:
    """Map Antigravity slugs (gemini-3.7-flash-high) to Gemini API ids."""
    n = (name or "").removeprefix("models/").strip()
    for suffix in ("-high", "-medium", "-low"):
        if n.endswith(suffix):
            n = n[: -len(suffix)]
            break
    return n or GOOGLE_FAST


def _google_sort_key(name: str) -> tuple:
    m = re.search(r"gemini-(\d+)(?:\.(\d+))?", name)
    major = int(m.group(1)) if m else 0
    minor = int(m.group(2) or 0) if m else 0
    if "flash" in name and "lite" not in name:
        kind = 0
    elif "pro" in name:
        kind = 1
    elif "lite" in name:
        kind = 2
    else:
        kind = 3
    if name.endswith("-high"):
        effort = 0
    elif name.endswith("-medium"):
        effort = 1
    elif name.endswith("-low"):
        effort = 2
    else:
        effort = 3
    return (-major, -minor, kind, effort, name)


def _cache_key(provider: str, rec: dict) -> str:
    return ":".join((
        provider,
        rec.get("mode") or "",
        rec.get("via") or "",
        "key" if (rec.get("key") or "").strip() else "nokey",
    ))


def peek_models(provider: str, rec: dict | None) -> list[str]:
    rec = rec or {}
    key = _cache_key(provider, rec)
    with _model_lock:
        hit = _model_cache.get(key)
    if hit:
        return hit[1]
    threading.Thread(
        target=list_models, args=(provider, rec), daemon=True).start()
    return []


def _store_models(cache_key: str, names: list[str]) -> list[str]:
    with _model_lock:
        _model_cache[cache_key] = (time.time() + MODEL_CACHE_SECS, names)
    return names


def _agy_models() -> list[str]:
    agy = _which("agy", "antigravity")
    if not agy:
        return []
    out = _run([agy, "models"], timeout=25)
    names: list[str] = []
    for line in out.splitlines():
        line = line.strip()
        if not line or line.lower().startswith("fetching"):
            continue
        slug = line.split("\t", 1)[0].split()[0].strip()
        if slug and slug not in names:
            names.append(slug)
    names.sort(key=_google_sort_key)
    return names


def _google_api_models(key: str) -> list[str]:
    names: list[str] = []
    token = ""
    skip = ("embedding", "imagen", "veo", "tts", "lyria", "image-preview",
            "native-audio", "live")
    for _ in range(8):
        query = {"pageSize": "200"}
        if token:
            query["pageToken"] = token
        data = http_json(
            "GET",
            "https://generativelanguage.googleapis.com/v1beta/models?"
            + urllib.parse.urlencode(query),
            None, {"x-goog-api-key": key}, timeout=15)
        for item in data.get("models") or []:
            methods = item.get("supportedGenerationMethods") or []
            if "generateContent" not in methods:
                continue
            name = (item.get("name") or "").removeprefix("models/")
            if not name or name in RETIRED_MODELS["google"]:
                continue
            lower = name.lower()
            if any(tok in lower for tok in skip):
                continue
            if name not in names:
                names.append(name)
        token = data.get("nextPageToken") or ""
        if not token:
            break
    names.sort(key=_google_sort_key)
    return names


def model_candidates(provider: str, requested: str, model_ok: dict) -> list[str]:
    cfg = PROVIDER_DEFAULTS.get(provider, {})
    retired = RETIRED_MODELS.get(provider, set())
    out: list[str] = []
    cached = model_ok.get(provider, "")
    names = (requested, cached, cfg.get("model"), *(cfg.get("fallbacks") or []))
    for name in names:
        if provider == "google":
            name = (name or "").removeprefix("models/").strip()
        if not name or name in retired or name in out:
            continue
        out.append(name)
    return out


def is_missing_model(exc: ProviderError) -> bool:
    if exc.status in (404, 400):
        blob = f"{exc} {exc.body}".lower()
        return any(tok in blob for tok in (
            "not found", "not_found", "does not exist", "no longer available",
            "invalid model", "unknown model", "model_not_found"))
    return False


def list_models(provider: str, rec: dict | None) -> list[str]:
    provider = canonical_provider(provider)
    rec = rec or {}
    key = (rec.get("key") or "").strip()
    cache_key = _cache_key(provider, rec)
    with _model_lock:
        hit = _model_cache.get(cache_key)
    if hit and hit[0] > time.time():
        return hit[1]

    names: list[str] = []
    try:
        if provider == "google":
            login = rec.get("mode") == "login" or rec.get("via") == "agy"
            if login or (not key and _which("agy", "antigravity")):
                names = _agy_models()
                if not names and key:
                    names = _google_api_models(key)
            elif key:
                names = _google_api_models(key)
                if not names:
                    names = _agy_models()
            else:
                names = _agy_models()
        elif provider == "openai" and key:
            data = http_json("GET", "https://api.openai.com/v1/models", None,
                             {"Authorization": f"Bearer {key}"}, timeout=12)
            names = sorted({
                m.get("id") for m in data.get("data") or []
                if isinstance(m.get("id"), str) and (
                    m["id"].startswith("gpt-") or m["id"].startswith("o"))
            }, reverse=True)
        elif provider == "anthropic" and key:
            data = http_json("GET", "https://api.anthropic.com/v1/models", None,
                             {"x-api-key": key, "anthropic-version": "2023-06-01"},
                             timeout=12)
            names = [m.get("id") for m in data.get("data") or []
                     if isinstance(m.get("id"), str)]
        elif provider == "ollama":
            host = (rec.get("host") or "http://127.0.0.1:11434").rstrip("/")
            data = http_json("GET", host + "/api/tags", None, {}, timeout=4)
            names = [m.get("name") for m in data.get("models") or []
                     if isinstance(m.get("name"), str)]
    except ProviderError:
        names = []

    if names:
        return _store_models(cache_key, names)
    return list(PROVIDER_DEFAULTS.get(provider, {}).get("fallbacks") or [])


def call_provider(stored: dict, provider: str, model: str, system: str,
                  prompt: str, model_ok: dict) -> str:
    provider = canonical_provider(provider)
    rec = stored.get(provider) or {}
    mode = rec.get("mode") or ("key" if rec.get("key") else "none")
    key = (rec.get("key") or "").strip()
    cfg = PROVIDER_DEFAULTS.get(provider) or {}

    if mode == "login" and rec.get("via") in {"agy", "codex", "claude", "gcloud"}:
        return _via_cli(rec["via"], model, system, prompt)

    if provider == "copilot":
        token = key or _gh_token()
        if not token:
            raise ProviderError("Sign in with GitHub or paste a Copilot-capable token.")
        return _copilot(token, model or cfg.get("model") or "gpt-4o", system, prompt)

    if provider == "ollama":
        url = (rec.get("host") or cfg.get("compat")
               or "http://127.0.0.1:11434/v1/chat/completions")
        return _compat(url, key, model or cfg["model"], system, prompt)

    if cfg.get("compat"):
        if not key:
            raise ProviderError(f"No API key saved for {cfg['label']}")
        extra = {}
        if provider == "openrouter":
            extra = {
                "HTTP-Referer": "https://github.com/nplata24s/arch-shell",
                "X-Title": "Arch Shell Agent Centre",
            }
        return _compat(cfg["compat"], key, model or cfg["model"], system, prompt, extra)

    if not key:
        raise ProviderError(
            f"No API key saved for {cfg.get('label', provider)}. "
            "Paste a key or Sign in on the Providers tab.")

    callers = {"openai": _openai, "anthropic": _anthropic, "google": _google}
    caller = callers.get(provider)
    if not caller:
        raise ProviderError(f"Unknown provider {provider}")

    errors: list[str] = []
    tried = model_candidates(provider, model, model_ok)
    live_tried = False
    idx = 0
    while idx < len(tried):
        candidate = tried[idx]
        idx += 1
        try:
            reply = caller(key, candidate, system, prompt)
            model_ok[provider] = candidate
            return reply
        except ProviderError as exc:
            errors.append(f"{candidate}: {exc}")
            if is_missing_model(exc) and not live_tried:
                live_tried = True
                for extra in list_models(provider, rec)[:8]:
                    if extra not in tried:
                        tried.append(extra)
            elif not is_missing_model(exc) and exc.status in (401, 403, 429, 408):
                raise
            continue
        except (KeyError, IndexError, TypeError, ValueError) as exc:
            errors.append(f"{candidate}: bad response ({exc})")
            continue
    raise ProviderError("All models failed. " + " | ".join(errors[:4]))
