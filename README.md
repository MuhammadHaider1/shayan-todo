# Shayan Todo — Agent-Driven Development Loop

A deliberately tiny **Todo list** app (FastAPI + vanilla JS) whose real purpose is to run a
complete **AI-agent software development cycle on its own**:

```
Linear ticket ──► agent (Codex CLI by default) implements ──► PR ──► GitHub Actions CI (lint+test+build)
        ──► review agent ──► human merge gate ──► gh auto-merge ──► ticket "Done"
        every step driven by scripts/run_loop.sh, zero hand-written app code
```

Built as a coding-evaluation submission. Stack: Python 3.12, FastAPI, uv, pytest, ruff,
GitHub Actions, Linear REST, an **agent-agnostic loop** (default **Codex CLI** — free with a
ChatGPT account; **Gemini CLI** is the fully-free fallback; **Claude Code** is supported but
needs a paid Pro plan), and a Python MCP server (`mcp_server/server.py`) so LLM assistants
can ask questions about the running app.

## How the loop runs end to end

`scripts/run_loop.sh` is the driver. One iteration, in order:

1. **Fetch a ticket** from Linear (`scripts/linear.py next`) — the oldest `Backlog` issue.
2. **Mark `In Progress`** in Linear (agent-visible, so the state machine is honest).
3. **Implement** — the ticket and the project contract in `CLAUDE.md` are handed to the
   configured agent (`scripts/agent.sh`, `AGENT=codex` by default → `codex exec
   --sandbox workspace-write --approve-for-me`). The agent writes the feature, adds
   `pytest` tests, runs `ruff check` + `pytest` until green, and commits. Nobody hand-edits
   the app.
4. **Open a PR** via `gh pr create` with the ticket key linked.
5. **CI** (`.github/workflows/ci.yml`) runs on the PR: `uv sync` → `ruff check` →
   `pytest` → `uv build` (tests **and** build).
6. **Review** — `scripts/review_pr.sh` hands the diff to a second agent run that
   returns `{approved, blockers, comments}`; findings are posted with `gh pr review`,
   and the PR is approved when clean (or moved back to `In Review` with blockers).
7. **Human merge gate** (permission-gating stretch) — the driver asks `Merge? [y/N]`
   unless `GATE_MERGE=0`.
8. **Auto-merge** — `gh pr merge --auto`. Branch protection on `main` requires the
   `test-build` check and one approving review, so GitHub merges the instant both pass.
9. **Mark `Done`** in Linear and append a note to `docs/memory.md` (cross-session memory).

Run `MODE=linear ./scripts/run_loop.sh` once per ticket; the full board empties ticket by
ticket. A `MODE=local` mode runs the exact same mechanics against
`scripts/demo_tickets.json` with no Linear/GitHub dependency.

## Agents and MCP servers used

| Piece | Tool | Role |
|---|---|---|
| Implementation agent | **Codex CLI** (default, free ChatGPT account) | Writes/edits app code, tests, commits |
| Review agent | same agent (`scripts/agent.sh`) | Reviews the PR diff, approves/requests changes |
| Discovery agent | same agent | Scans repo for dead code/missing tests/risks |
| Pluggable backends | `AGENT=codex` (default) · `gemini` (fully free) · `claude` (paid) | One prompt interface, three CLIs |
| Specialist subagents | `.claude/agents/planner.md`, `coder.md` | Stretch: plan-then-code split (`AGENT_SPLIT=1`, Claude Code only) |
| Ticket manager | **Linear REST** (`scripts/linear.py`, stdlib-only) | Seed, fetch, move tickets between states |
| App MCP server | **`mcp_server/server.py`** (Python MCP SDK) | Live state + source explanations to LLMs |
| Linear MCP | not required — status changes are driven by `scripts/linear.py` for determinism | — |

## How to connect the MCP server to Codex and Claude Code

Start nothing manually; each client launches the server on demand.

**Codex CLI** (default, free):
```bash
codex mcp add shayan-todo -- uv run mcp_server/server.py
```
(or in `~/.codex/config.toml`):
```toml
[mcp_servers.shayan-todo]
command = "uv"
args = ["run", "mcp_server/server.py"]
```

**Claude Code** — auto-loads on project open via `.mcp.json`:
```json
{ "mcpServers": { "shayan-todo": { "command": "uv", "args": ["run", "mcp_server/server.py"] } } }
```
(equivalent: `claude mcp add --scope project shayan-todo -- uv run mcp_server/server.py`)

**Gemini CLI** (fully free alternative):
```bash
gemini mcp add shayan-todo -- uv run mcp_server/server.py
```

> Note: the evaluation asked for *both* Codex and Claude Code. The MCP server and its
> `.mcp.json` wiring for Claude Code are in this repo and ready, but Claude Code itself
> requires a $20/mo subscription which this project deliberately avoids — so the live Q&A
> demo runs through **Codex** and **Gemini** instead, and the Claude Code path is documented
> and plug-and-play.

**Then ask any assistant** (all answers cite the real code / live state):
- “what does the win check do?”  → `explain_source("win check")`
- “where is state stored?”        → `explain_source("state")` + `get_todos()`
- “how many todos are done?”      → `todo_stats()`

Tools (from `mcp_server/server.py`): `get_todos`, `get_todo`, `todo_stats`, `add_todo`,
`explain_source`. State lives in `data/todos.json` (via `app/storage.py`); answers come
from that live state plus the source that generates it, so they stay accurate.

## Setup checklist (one-time, ~10 minutes)

```bash
# 1. GitHub (done already: public repo + auto-merge + branch protection are configured)
#    https://github.com/MuhammadHaider1/shayan-todo

# 2. Linear — linear.app -> Settings -> API -> create a personal key
export LINEAR_API_KEY=lin_api_...            # and: export PATH="$HOME/node22/bin:$PATH"

# 3. seed tickets
python3 scripts/linear.py seed

# 4. log your agents in once (interactive, needed only the first time; free accounts suffice)
codex login       # Codex: free ChatGPT account
# or, fully free alternative:  (skip if you want only Codex)
#   npm i -g @google/gemini-cli && gemini   # then put GEMINI_API_KEY in .env

# 5. run the loop (repeat until the board is empty)
GATE_MERGE=1 ./scripts/run_loop.sh          # uses AGENT=codex by default
# AGENT=gemini GATE_MERGE=1 ./scripts/run_loop.sh   # fully-free option
```

## Discovery (dead code / missing tests / risks)

`scripts/discovery.sh` runs the discovery agent over the working tree, writes
`docs/discovery-<date>.md`, and with `--post-issue` files a GitHub issue labelled
`discovery`. A scheduled GitHub Actions job (`.github/workflows/discovery.yml`, weekly +
manual) does the same in CI using the **free** Gemini CLI and a `GEMINI_API_KEY` secret.
Because every feature is agent-generated, real dead code and blank spots tend to appear —
the scan reports them with `file:line` and a suggested fix.

## Stretch goals (all implemented)

- **Cross-session memory** — `CLAUDE.md` + `docs/decisions.md` + `docs/memory.md`; the
  implementation prompt tells every agent to read them before starting and append after.
- **Permission gating** — `GATE_MERGE=1` pauses before merge and waits for `y`.
- **Second specialist agent** — `AGENT_SPLIT=1` runs the planner subagent
  (`.claude/agents/planner.md`, no code) then the coder subagent (`.claude/agents/coder.md`).

## Honesty — what works and what does not

- **Works now, verified on this machine:** repo + branch protection + auto-merge
  configured live; CI genuinely ran (lint caught a real newline bug, fixed, now green);
  local `MODE=local` ticket mechanics tested; MCP server boots and returns live state once
  `app/storage.py` exists; all lint/tests/build green locally.
- **Needs your accounts to fire end-to-end:** the Linear↔GitHub loop steps need (a) a
  `LINEAR_API_KEY` and (b) one interactive login (`codex login` with a free ChatGPT account,
  or a free Google AI Studio key for `AGENT=gemini`). OAuth can’t be done non-interactively,
  so until those exist the intermediate states (`In Progress`→`In Review`→`Done`) haven’t
  been recorded live — the plumbing is all in place and CI-tested at every layer.
- **No Claude Code in the live demo:** Claude Code has no free tier (verified Aug 2026; it
  needs a $20/mo Pro plan), so the loop's default agent is **Codex** (free) with **Gemini**
  (fully free) as fallback. Claude Code is fully supported via `AGENT=claude` and its
  `.mcp.json` wiring is ready, but it is not exercised in the demo for cost reasons.
- **Known gap:** `app/storage.py`, `app/main.py`, and the frontend do not exist yet — by
  design, ticket `LOCAL-1`/`SHY-1` is what creates them, so the "agent builds the app"
  story is provably true. The MCP server already returns an honest `error` for those until
  the ticket lands.

## What I would do next with more time

- Run the full linear loop live (once key + agent login are in) and record it.
- Switch storage to SQLite behind the same `app/storage.py` interface (adapter already
  isolated), adding a persistence-migration ticket.
- Add a Claude-Code lane alongside Codex to compare output on the same tickets (once a
  budget exists).
- Add PR draft/`In Review` ↔ CI-failure hooks back into Linear automatically.
- Post each merged diff summary into Linear automatically (release-notes-style).