# Agent Centre

Local agent teams for Arch Shell. The UI is `shell/AgentCentrePopup.qml`. The backend is `daemon/arch_agentd.py` (stdlib only, no pip).

## Providers

Credentials live in `~/.config/arch-shell/agent/providers.json` (mode 600). Each
provider accepts an **API key**. Google, OpenAI, Anthropic, and Copilot also
accept **Sign in**, which opens that vendor's official CLI so usage stays on
your subscription:

| Provider | API key | Sign in (subscription) |
| --- | --- | --- |
| Google Gemini | AI Studio key | Antigravity CLI (`agy`) for Google AI Pro / Ultra. `gcloud` ADC is a fallback. |
| OpenAI / ChatGPT | platform.openai.com key | Codex CLI (`codex login`) for ChatGPT Plus / Pro |
| Anthropic / Claude | console.anthropic.com key | Claude Code for Claude Pro / Max |
| GitHub Copilot | GitHub token | `gh auth login` — uses your Copilot plan |
| xAI, DeepSeek, Mistral, Groq, OpenRouter | API key | — |
| Ollama | none (local) | — |

Google no longer serves Gemini CLI / Code Assist logins for personal AI Pro
accounts (that rail ended 18 June 2026). Sign in for Google AI Pro uses
[Antigravity CLI](https://www.antigravity.google/docs/cli/install/). A paid
Gemini API key still works without signing in.

**Use existing login** attaches a session you already completed in the terminal
(`codex login`, `claude`, `agy`, `gh auth login`).

Gemini models are retired often and return HTTP 404. The daemon:

- defaults to generation-free aliases (`gemini-flash-latest`)
- skips known-retired ids (`gemini-2.0-flash`, …)
- on 404, lists live models for that API key and retries
- uses the same fallback walk for OpenAI and Anthropic

Leave an agent's model blank to let this happen automatically.

## Hierarchy

Each **team** has:

- optional parent team
- a lead agent
- approval policy: `user` (you), `higher` (nearest lead/director), `auto`
- communication: `isolated` / `team` / `org` / `open`
- standing rules (chips + custom text)

Each **agent** has:

- rank: worker / lead / director
- reports-to
- approval override (`inherit` uses the team)
- personal rules on top of the team's

Permission prompts appear at the top of the panel. You can always Approve or Deny, even when a higher agent is deciding. If that agent replies `ESCALATE`, the request bubbles up.

Agents may end a reply with `{"actions":[...]}` to ask, assign work, message another agent/team, or escalate — gated by the team's communication policy and rank.
