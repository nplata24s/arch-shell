#!/usr/bin/env bash
# Install the official CLIs Agent Centre uses for subscription sign-in.
# Safe to re-run. Official curl installers do not need root.
# github-cli and ollama come from pacman when sudo is available.
set -uo pipefail

BIN="${HOME}/.local/bin"
mkdir -p "$BIN"
export PATH="${BIN}:${PATH}"

ok=0
fail=0

have() { command -v "$1" >/dev/null 2>&1; }

ensure_path_rc() {
  local line='export PATH="$HOME/.local/bin:$PATH"'
  local rc
  for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.bash_profile"; do
    [[ -f "$rc" ]] || continue
    grep -Fq '.local/bin' "$rc" && continue
    printf '\n%s\n' "$line" >> "$rc"
  done
}

mark_ok() { ok=$((ok + 1)); }
mark_fail() { fail=$((fail + 1)); echo "    $1" >&2; }

install_agy() {
  if have agy || have antigravity; then
    echo "==> Antigravity CLI already installed ($(agy --version 2>/dev/null | head -1))"
    mark_ok
    return
  fi
  echo "==> Installing Antigravity CLI (agy)..."
  if curl -fsSL https://antigravity.google/cli/install.sh | bash; then
    have agy || have antigravity && mark_ok && return
  fi
  mark_fail "Antigravity CLI did not land on PATH. Retry later or see https://www.antigravity.google/docs/cli/install/"
}

install_codex() {
  if have codex; then
    echo "==> Codex CLI already installed ($(codex --version 2>/dev/null | head -1))"
    mark_ok
    return
  fi
  echo "==> Installing Codex CLI..."
  if curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=true sh; then
    have codex && mark_ok && return
  fi
  mark_fail "Codex CLI install failed. https://developers.openai.com/codex/cli"
}

install_claude() {
  if have claude; then
    echo "==> Claude Code already installed ($(claude --version 2>/dev/null | head -1))"
    mark_ok
    return
  fi
  echo "==> Installing Claude Code..."
  if curl -fsSL https://claude.ai/install.sh | bash; then
    have claude && mark_ok && return
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
    have "$bin" && mark_ok && return
  fi
  mark_fail "${pkg} did not install. Agent Centre Sign in for ${name} will stay unavailable."
}

ensure_path_rc
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
if ((fail)); then
  echo "${fail} CLI(s) did not install. Re-run:  ~/.config/arch-shell/scripts/install-login-clis.sh"
fi
exit 0
