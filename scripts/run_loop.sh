#!/usr/bin/env bash
#
# run_loop.sh — the agent-driven development loop. One iteration:
#
#   ticket -> In Progress -> agent (claude/codex/gemini) implements + tests + commits
#   -> PR -> GitHub Actions CI (lint/test/build) -> review agent
#   -> approve/request-changes -> human merge gate -> gh pr merge --auto
#   -> mark Done -> append cross-session memory
#
# Modes
#   MODE=linear  (default) tickets come from Linear (needs LINEAR_API_KEY)
#   MODE=local   tickets come from scripts/demo_tickets.json (no GitHub/Linear needed)
#
# Env knobs
#   REPO          owner/name of the GitHub repo (default: MuhammadHaider1/shayan-todo)
#   GATE_MERGE    1 = ask a human before merging (default), 0 = auto
#   AGENT         claude | codex | gemini  (default codex — free with a ChatGPT account)
#   AGENT_SPLIT   1 = planner then coder subagents (Claude Code only; stretch), 0 = one agent
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${MODE:-linear}"
REPO="${REPO:-MuhammadHaider1/shayan-todo}"
BASE="${BASE:-main}"
GATE_MERGE="${GATE_MERGE:-1}"
AGENT="${AGENT:-codex}"
AGENT_SPLIT="${AGENT_SPLIT:-0}"
PREFIX="feat"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { log "STOP: $*"; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || fail "missing binary: $1 (install it)"; }
require gh
require git
require uv
require python3

log "Agent loop — iteration starting (mode=$MODE, repo=$REPO, agent=$AGENT)"

# --- auth sanity checks -----------------------------------------------------
if ! bash scripts/agent.sh check; then
  case "$AGENT" in
    claude) fail "Claude Code is not logged in. Run 'claude' once to sign in." ;;
    codex)  fail "Codex is not logged in. Run 'codex login' (free ChatGPT account works), or set AGENT=gemini." ;;
    gemini) fail "Gemini CLI missing or GEMINI_API_KEY not set. Install via 'npm i -g @google/gemini-cli' and set the key." ;;
  esac
fi
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated (needed for PRs + merges). Run 'gh auth login'."
git config user.name >/dev/null 2>&1 || { git config user.name "Agent Loop"; }
git config user.email >/dev/null 2>&1 || { git config user.email "agent-loop@shayan.local"; }
if [ "$AGENT_SPLIT" = "1" ] && [ "$AGENT" != "claude" ]; then
  fail "AGENT_SPLIT (planner/coder subagents) currently requires AGENT=claude (Claude Code)."
fi

# --- 1. fetch next ticket ---------------------------------------------------
declare TID IDKEY TITLE DESC
if [ "$MODE" = "linear" ]; then
  TICKET_JSON="$(python3 scripts/linear.py next || true)"
  [ -n "$TICKET_JSON" ] || fail "could not read a Linear ticket (is LINEAR_API_KEY set?)"
  [ "$TICKET_JSON" != "NO_TICKET" ] || { log "No Backlog tickets left in Linear. Loop complete."; exit 0; }
else
  TICKET_JSON="$(python3 - <<'PY'
import json
p = "scripts/demo_tickets.json"
data = json.load(open(p))
for t in data:
    if t["status"] == "Backlog":
        t["status"] = "In Progress"
        json.dump(data, open(p, "w"), indent=2)
        print(json.dumps({"id": t["key"], "identifier": t["key"],
                          "title": t["title"], "description": t["description"]}))
        break
else:
    print("NO_TICKET")
PY
)"
  [ "$TICKET_JSON" = "NO_TICKET" ] && { log "No local Backlog tickets left. Loop complete."; exit 0; }
fi

TID="$(printf '%s' "$TICKET_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')"
IDKEY="$(printf '%s' "$TICKET_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["identifier"])')"
TITLE="$(printf '%s' "$TICKET_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["title"])')"
DESC="$(printf '%s' "$TICKET_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["description"])')"

log "Ticket: $IDKEY — $TITLE"
[ "$MODE" = "linear" ] && python3 scripts/linear.py set-state "$TID" "In Progress"

# --- 2. branch ---------------------------------------------------------------
git fetch origin -q >/dev/null 2>&1 || true
git checkout "$BASE" >/dev/null 2>&1 || fail "branch $BASE not found — push the repo first"
TITLE_SLUG="$(printf '%s' "$TITLE" | tr -cs 'A-Za-z0-9' '-' | tr '[:upper:]' '[:lower:]' | sed 's/^-//;s/-$//' | cut -c1-40)"
BRANCH="${PREFIX}/$(printf '%s' "$IDKEY" | tr '[:upper:]' '[:lower:]')-${TITLE_SLUG}"
git checkout -b "$BRANCH"
log "Working on branch: $BRANCH"

# --- 3. implement with agents -------------------------------------------------
memory_note="$ROOT/docs/memory.md"
ticket_block="Ticket $IDKEY: $TITLE

$DESC"

if [ "$AGENT_SPLIT" = "1" ]; then
  log "Planner subagent drafting an implementation plan..."
  PLAN="$(claude -p --dangerously-skip-permissions \
    "Invoke the @planner subagent (.claude/agents/planner.md) for this ticket and return the plan it produces verbatim.
Ticket: $ticket_block")"
  log "Plan received. Coder subagent implementing..."
  claude -p --dangerously-skip-permissions \
    "Invoke the @coder subagent (.claude/agents/coder.md) to implement this ticket against the planner's plan.

Ticket:
$ticket_block

Plan:
$PLAN

Tell the coder to read CLAUDE.md, docs/decisions.md and docs/memory.md first, make the
pipeline green (uv run ruff check app mcp_server tests scripts && uv run pytest -q),
commit, and append a note to docs/memory.md. Nobody pushes or opens a PR."
else
  log "Agent ($AGENT) implementing the ticket (vibe coding step, no human edits)..."
  bash scripts/agent.sh run \
    "You are implementing the ticket below on branch $BRANCH.

$ticket_block

Rules (read CLAUDE.md first — the interface contract is mandatory):
1. Implement exactly this ticket's scope; add/update tests in tests/.
2. Make the pipeline green before committing:
     uv run ruff check app mcp_server tests scripts
     uv run pytest -q
3. git add + commit with message: \"$IDKEY: $TITLE\"
4. Append a short memory note to $memory_note (read docs/decisions.md first).
5. Do NOT push, do NOT open a PR, do NOT touch Linear or GitHub. I (the driver) handle those.
Finish your final message with: WORK COMPLETE"
fi

if git diff --quiet "$BASE".."$BRANCH" 2>/dev/null && [ "$(git log --oneline "$BASE".."$BRANCH" | wc -l)" -eq 0 ]; then
  fail "agent made no commits — aborting before PR"
fi
log "Pushing branch..."
git push -u origin "$BRANCH" 2>&1 | tail -2

# --- 4. open PR ---------------------------------------------------------------
PR_BODY="Closes Linear: ${IDKEY}

${DESC}

_Shipment of the agent-driven loop: Linear -> implement -> CI -> review -> auto-merge (run_loop.sh)._"
PR_URL="$(gh pr create --repo "$REPO" --base "$BASE" --head "$BRANCH" \
  --title "$IDKEY: $TITLE" --body "$PR_BODY")"
[ -n "$PR_URL" ] || fail "PR creation failed"
log "PR: $PR_URL"

# --- 5. wait for CI (lint + test + build in GitHub Actions) --------------------
log "Waiting for CI checks..."
CI_OK=1
gh pr checks "$PR_URL" --watch --interval 10 --fail-fast || CI_OK=0
if [ "$CI_OK" != 1 ]; then
  [ "$MODE" = "linear" ] && python3 scripts/linear.py set-state "$TID" "In Review"
  fail "CI failed on $IDKEY — ticket moved to In Review for human attention"
fi

# --- 6. review agent ------------------------------------------------------------
log "Running the review agent on the PR diff..."
bash scripts/review_pr.sh "$PR_URL" "$BRANCH" "$TID" "$IDKEY" "$MODE"

# --- 7. human merge gate (permission gating, stretch) ---------------------------
if [ "$GATE_MERGE" = "1" ]; then
  if [ -t 0 ]; then
    read -r -p "CI green + review clean. Merge $IDKEY into $BASE? [y/N] " ans
    APPROVE=0
    case "$ans" in y|Y|yes|YES) APPROVE=1;; esac
  else
    log "Merge gate enabled but no TTY — deferring merge (set GATE_MERGE=0 to auto-merge)."
    APPROVE=0
  fi
  if [ "$APPROVE" != 1 ]; then
    [ "$MODE" = "linear" ] && python3 scripts/linear.py set-state "$TID" "In Review"
    log "Human deferred the merge. Ticket $IDKEY left in review. Run the loop again to continue."
    exit 0
  fi
else
  log "GATE_MERGE=0 — auto-approving merge."
fi

[ "$MODE" = "linear" ] && python3 scripts/linear.py set-state "$TID" "In Review"

# --- 8. auto-merge once CI passes and review is clean ----------------------------
log "Enabling auto-merge (GitHub merges as soon as checks + approval are satisfied)..."
gh pr merge "$PR_URL" --auto --squash --delete-branch \
  --subject "$IDKEY: $TITLE" --body "Merged by the agent loop (run_loop.sh)."
log "Waiting for the merge..."
for _ in $(seq 1 90); do
  MERGED="$(gh pr view "$PR_URL" --json merged -q .merged)"
  [ "$MERGED" = "true" ] && break
  sleep 10
done
[ "$MERGED" = "true" ] || fail "auto-merge did not complete within ~15 min: $PR_URL"

git fetch origin -q
git checkout "$BASE" >/dev/null 2>&1
git pull -q
git branch -D "$BRANCH" >/dev/null 2>&1 || true

# --- 9. mark Done + memory --------------------------------------------------------
[ "$MODE" = "linear" ] && python3 scripts/linear.py set-state "$TID" "Done"
log "Loop complete: $IDKEY merged into $BASE. Run scripts/run_loop.sh again for the next ticket."