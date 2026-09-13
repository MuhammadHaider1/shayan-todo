# Decisions

## 2026-09-13 — Stack & storage
- **App**: Todo list, FastAPI + vanilla JS frontend (no build step).
- **Backend**: FastAPI served with uvicorn; interface contract in `CLAUDE.md`.
- **Storage**: flat JSON file at `data/todos.json` via `app/storage.py` — keeps the
  "where is state stored?" answer simple and truthful, and lets the MCP server read live state.
- **MCP**: Python FastMCP (`mcp_server/server.py`), stdio transport, tools:
  `get_todos`, `get_todo`, `add_todo`, `todo_stats`, `explain_source`.
- **Loop**: driven by `scripts/run_loop.sh`; Linear owns tickets, GitHub Actions owns CI,
  `gh pr merge --auto` owns auto-merge, Claude Code agents own implementation + review + discovery.
- **Agents**: headless agent backend is pluggable via `AGENT` env in `scripts/agent.sh`:
  - `codex` (default, free with a ChatGPT account) — implementation/review/discovery,
  - `gemini` (fully free via Google AI Studio key),
  - `claude` (Claude Code — needs a paid Pro plan, configured but not default).
  All three can talk to the app through the MCP server (`mcp_server/server.py`).