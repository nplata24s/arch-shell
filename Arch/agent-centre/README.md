# Agent Centre

Local agent teams for Arch Shell. The UI is `shell/AgentCentrePopup.qml`. The backend is `daemon/arch_agentd.py` (stdlib only, no pip).

## Providers

Keys live in `~/.config/arch-shell/agent/providers.json` (mode 600).

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
