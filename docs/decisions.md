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
- **Agents**: local `claude` CLI (implementation/review/discovery) + `codex` CLI must both be
  able to talk to the app through the MCP server (Phase later).