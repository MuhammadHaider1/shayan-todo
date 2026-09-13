#!/usr/bin/env bash
#
# agent.sh — run the configured AI coding agent headlessly.
#
# AGENT=<claude|codex|gemini>   (default: codex — free with a ChatGPT account)
#
# Usage:
#   agent.sh check                exit 0 if the agent is installed + logged in
#   agent.sh run <prompt...>      run the agent on a prompt, stream stdout
#
set -euo pipefail

AGENT="${AGENT:-codex}"

check() {
  case "$AGENT" in
    claude)
      command -v claude >/dev/null 2>&1 || return 1
      claude -p "reply with exactly: ok" >/dev/null 2>&1
      ;;
    codex)
      command -v codex >/dev/null 2>&1 || return 1
      codex login status >/dev/null 2>&1
      ;;
    gemini)
      command -v gemini >/dev/null 2>&1 || return 1
      [ -n "${GEMINI_API_KEY:-}" ]
      ;;
    *)
      echo "agent.sh: unknown AGENT=$AGENT (use claude|codex|gemini)" >&2
      return 1
      ;;
  esac
}

run() {
  [ "$#" -ge 1 ] || { echo "agent.sh: usage: agent.sh run <prompt>" >&2; return 1; }
  PROMPT="$*"
  case "$AGENT" in
    claude)
      claude -p --dangerously-skip-permissions "$PROMPT"
      ;;
    codex)
      codex exec --sandbox workspace-write --approve-for-me "$PROMPT" </dev/null
      ;;
    gemini)
      gemini --prompt "$PROMPT" --yolo </dev/null 2>/dev/null || gemini -p "$PROMPT" </dev/null
      ;;
    *)
      echo "agent.sh: unknown AGENT=$AGENT (use claude|codex|gemini)" >&2
      return 1
      ;;
  esac
}

case "${1:-}" in
  check) check ;;
  run) shift; run "$@" ;;
  *) echo "usage: agent.sh <check|run>" >&2; exit 1 ;;
esac