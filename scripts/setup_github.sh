#!/usr/bin/env bash
#
# setup_github.sh [owner/repo]
#
# One-time plumbing: creates the public repo from this directory, enables
# auto-merge, and configures branch protection on main so that
# "CI passes + 1 approving review" is exactly what auto-merges.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPO="${1:-MuhammadHaider1/shayan-todo}"
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

log "Ensuring repo $REPO exists (public)..."
if gh repo view "$REPO" >/dev/null 2>&1; then
  gh repo edit "$REPO" --visibility public
else
  gh repo create "$NAME" --public --source . --remote origin --push
fi

log "Ensuring git identity (only if unset)..."
git config user.name  >/dev/null 2>&1 || git config user.name  "$(gh api user -q .login)"
git config user.email >/dev/null 2>&1 || git config user.email "$(gh api user -q '.email // .login+"@users.noreply.github.com"')"

log "Enabling allow-auto-merge on $REPO..."
gh repo edit "$REPO" --enable-auto-merge

log "Creating the 'discovery' label..."
gh label create discovery --color 0E8A16 \
  --description "Findings from the agent discovery scan" --force >/dev/null 2>&1 || true

log "Protecting main: require CI (test-build) + 1 approving review, no force push..."
gh api -X PUT "repos/${REPO}/branches/main/protection" \
  -H "Accept: application/vnd.github+json" \
  --input - <<'JSON'
{
  "required_status_checks": {"strict": true, "contexts": ["test-build"]},
  "enforce_admins": false,
  "required_pull_request_reviews": {"required_approving_review_count": 1},
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": false
}
JSON

log "GitHub ready: repo=$REPO | auto-merge on | main protected (CI + review required)"
log "Next: export LINEAR_API_KEY=<...> then run scripts/seed_linear.py"