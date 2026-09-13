#!/usr/bin/env bash
#
# review_pr.sh <pr_url> <branch> <ticket_id> <ticket_key> <mode>
#
# Runs the review agent (Claude Code) on a PR diff, posts findings to the PR via gh,
# approves when clean, or requests changes and moves the Linear ticket to In Review.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PR_URL="${1:?pr url}"
BRANCH="${2:?branch}"
TID="${3:?ticket id}"
IDKEY="${4:?ticket key}"
MODE="${5:-linear}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

BASE="$(gh pr view "$PR_URL" --json baseRefName -q .baseRefName)"

git fetch origin -q >/dev/null 2>&1 || true
DIFF_STAT="$(git diff "origin/${BASE}...${BRANCH}" --stat || true)"
DIFF="$(git diff "origin/${BASE}...${BRANCH}" || true)"

log "Reviewing $IDKEY ($BRANCH) diff:"
printf '%s\n' "$DIFF_STAT"

REVIEW_JSON="$(claude -p --dangerously-skip-permissions \
"You are the review agent for PR $IDKEY ($PR_URL), branch $BRANCH, base $BASE.
Criteria: interface contract in CLAUDE.md, correctness, missing/weak tests, dead code,
security issues, scope creep, unescaped user input.

DIFF:
$DIFF

Output EXACTLY one JSON object with this shape and nothing else:
{\"approved\": true|false, \"blockers\": [\"...\"], \"comments\": [\"...\"]}
blockers = problems that MUST be fixed before merge; comments = suggestions." )"

APPROVED="$(printf '%s' "$REVIEW_JSON" | python3 -c 'import sys,json;print(str(json.load(sys.stdin).get("approved",False)).lower())')"
COMMENT_BODY="$(printf '%s' "$REVIEW_JSON" | python3 -c '
import sys, json, textwrap
try:
    d = json.load(sys.stdin)
except Exception as e:
    d = {"approved": False, "comments": [f"[could not parse review JSON: {e}]"]}
lines = ["## Review agent findings", ""]
lines.append("**Approved:** " + str(d.get("approved", False)))
if d.get("blockers"):
    lines += ["**Blockers:**"] + [f"- {b}" for b in d["blockers"]]
if d.get("comments"):
    lines += ["**Comments:**"] + [f"- {c}" for c in d["comments"]]
print("\n".join(lines))
')"

log "Posting review findings..."
if [ "$APPROVED" = "false" ]; then
  gh pr review "$PR_URL" --request-changes --body "$COMMENT_BODY"
  [ "$MODE" = "linear" ] && python3 scripts/linear.py set-state "$TID" "In Review"
  echo "REVIEW_BLOCKER $IDKEY" >&2
  exit 1
else
  gh pr review "$PR_URL" --approve --body "$COMMENT_BODY"
  echo "REVIEW_CLEAN $IDKEY"
fi