#!/usr/bin/env bash
#
# discovery.sh [--post-issue]
#
# Runs the discovery agent (Claude Code) over the working tree and reports:
# dead code, missing tests, risks, and improvement ideas.
# - Always writes a report to docs/discovery-<date>.md
# - With --post-issue, also opens a GitHub issue labelled "discovery".
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

POST="${1:-}"
STAMP="$(date +%Y-%m-%d)"
REPORT="docs/discovery-${STAMP}.md"
REPO="${REPO:-MuhammadHaider1/shayan-todo}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

log "Running discovery agent over the repo..."
FINDINGS="$(claude -p --dangerously-skip-permissions \
"You are the discovery agent for this repo. Read CLAUDE.md for context.
Explore the codebase (app/, tests/, static/, scripts/, mcp_server/) and produce a findings report.

Find and report REAL, specific issues (cite file:line):
1. Dead code (unused imports, functions never called, orphan files)
2. Missing or weak tests
3. Risks (security, correctness, data loss, concurrency, storage format)
4. Improvement ideas (smallest first)
5. Anything odd discovered.

Output only a concise markdown report.")"

{
  printf '# Discovery report — %s\n\n' "$STAMP"
  printf 'Generated automatically by scripts/discovery.sh (agent-driven).\n\n'
  printf '%s\n' "$FINDINGS"
} > "$REPORT"

log "Report written to $REPORT"
printf '%s\n' "$FINDINGS" | head -40

if [ "$POST" = "--post-issue" ]; then
  log "Opening GitHub issue..."
  gh issue create --repo "$REPO" \
    --title "Discovery: agent scan $STAMP" \
    --body "$(cat "$REPORT")" \
    --label discovery
fi