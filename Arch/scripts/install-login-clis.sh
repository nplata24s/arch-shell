#!/usr/bin/env bash
# Install the official CLIs used for Agent Centre subscription sign-in.
# Safe to re-run. Does not need root.
set -euo pipefail

BIN="${HOME}/.local/bin"
mkdir -p "$BIN"
export PATH="${BIN}:${PATH}"

need() { command -v "$1" >/dev/null 2>&1; }

install_agy() {
  if need agy; then
    echo "==> Antigravity CLI already installed ($(agy --version 2>/dev/null | head -1))"
    return
  fi
  echo "==> Installing Antigravity CLI (agy)..."
  curl -fsSL https://antigravity.google/cli/install.sh | bash
}

install_codex() {
  if need codex; then
    echo "==> Codex CLI already installed ($(codex --version 2>/dev/null | head -1))"
    return
  fi
  echo "==> Installing Codex CLI..."
  curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=true sh
}

install_claude() {
  if need claude; then
    echo "==> Claude Code already installed ($(claude --version 2>/dev/null | head -1))"
    return
  fi
  echo "==> Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
}

install_agy
install_codex
install_claude

echo
echo "Login CLIs:"
printf '  agy    %s\n' "$(command -v agy || echo missing)"
printf '  codex  %s\n' "$(command -v codex || echo missing)"
printf '  claude %s\n' "$(command -v claude || echo missing)"
echo "Open Agent Centre → Providers and click Sign in for each plan you use."
