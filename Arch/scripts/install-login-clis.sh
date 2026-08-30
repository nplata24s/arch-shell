#!/usr/bin/env bash
# Install the official CLIs Agent Centre uses for subscription sign-in.
# Safe to re-run. Does not fail the desktop install if one vendor is down.
set -uo pipefail

BIN="${HOME}/.local/bin"
mkdir -p "$BIN"
export PATH="${BIN}:${HOME}/.npm-global/bin:${PATH}"

ok=0
fail=0

have() { command -v "$1" >/dev/null 2>&1; }

ensure_path_rc() {
  local line='export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"'
  local rc
  for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.bash_profile" "${HOME}/.profile"; do
    if [[ ! -f "$rc" ]]; then
      printf '%s\n' "$line" > "$rc"
      continue
    fi
    grep -Fq '.local/bin' "$rc" && continue
    printf '\n%s\n' "$line" >> "$rc"
  done
}

ensure_npm_prefix() {
  have npm || return 0
  mkdir -p "${HOME}/.npm-global"
  npm config set prefix "${HOME}/.npm-global" >/dev/null 2>&1 || true
}

mark_ok() { ok=$((ok + 1)); }
mark_fail() { fail=$((fail + 1)); echo "    $1" >&2; }

npm_global() {
  have npm || return 1
  npm install -g "$1" >/dev/null
}

install_agy() {
  if have agy || have antigravity; then
    echo "==> Antigravity CLI already installed"
    mark_ok
    return
  fi
  echo "==> Installing Antigravity CLI (agy)..."
  if curl -fsSL https://antigravity.google/cli/install.sh | bash; then
    if have agy || have antigravity; then
      mark_ok
      return
    fi
  fi
  mark_fail "Antigravity CLI did not land on PATH. https://www.antigravity.google/docs/cli/install/"
}

install_codex() {
  if have codex; then
    echo "==> Codex CLI already installed"
    mark_ok
    return
  fi
  echo "==> Installing Codex CLI..."
  if curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=true sh; then
    if have codex; then
      mark_ok
      return
    fi
  fi
  echo "    official installer missed PATH, trying npm..."
  if npm_global @openai/codex && have codex; then
    mark_ok
    return
  fi
  mark_fail "Codex CLI install failed. https://developers.openai.com/codex/cli"
}

install_claude() {
  if have claude; then
    echo "==> Claude Code already installed"
    mark_ok
    return
  fi
  echo "==> Installing Claude Code..."
  if curl -fsSL https://claude.ai/install.sh | bash; then
    if have claude; then
      mark_ok
      return
    fi
  fi
  echo "    official installer missed PATH, trying npm..."
  if npm_global @anthropic-ai/claude-code && have claude; then
    mark_ok
    return
  fi
  mark_fail "Claude Code install failed. https://code.claude.com/docs/en/setup"
}

install_pkg() {
  local name="$1" bin="$2" pkg="$3"
  if have "$bin"; then
    echo "==> ${name} already installed ($(command -v "$bin"))"
    mark_ok
    return
  fi
  if ! have pacman; then
    mark_fail "${name} needs ${pkg}, and pacman is not available."
    return
  fi
  echo "==> Installing ${name} (${pkg})..."
  if sudo pacman -S --needed --noconfirm "$pkg"; then
    if have "$bin"; then
      mark_ok
      return
    fi
  fi
  mark_fail "${pkg} did not install. Agent Centre Sign in for ${name} will stay unavailable."
}

ensure_path_rc
ensure_npm_prefix
install_agy
install_codex
install_claude
install_pkg "GitHub CLI (Copilot)" gh github-cli
install_pkg "Ollama (local models)" ollama ollama

echo
echo "Login CLIs:"
printf '  agy / antigravity  %s\n' "$(command -v agy || command -v antigravity || echo missing)"
printf '  codex              %s\n' "$(command -v codex || echo missing)"
printf '  claude             %s\n' "$(command -v claude || echo missing)"
printf '  gh                 %s\n' "$(command -v gh || echo missing)"
printf '  ollama             %s\n' "$(command -v ollama || echo missing)"
echo "Open Agent Centre → Providers and click Sign in for each plan you use."
echo "Ollama has no models until you run:  ollama pull llama3.2"
if ((fail)); then
  echo "${fail} CLI(s) did not install. Re-run:  ~/.config/arch-shell/scripts/install-login-clis.sh"
fi
exit 0
