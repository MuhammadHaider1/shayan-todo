# Shayan Todo — Project Contract

You are one of the AI agents working on **Shayan Todo**: a two-player-free, simple Todo
list app with a **FastAPI backend** and a **vanilla JS frontend**, built and shipped
entirely through the agent loop.

## Interface contract (do not break)

The MCP server and the frontend depend on these exact shapes:

- **Storage**: all todos live in `data/todos.json` (created at runtime, gitignored).
  Use the helper module `app/storage.py` with exactly these functions:
  - `list_todos() -> list[dict]`
  - `add_todo(text: str) -> dict`
  - `update_todo(todo_id: int, **changes) -> dict` (raises `KeyError` if missing)
  - `delete_todo(todo_id: int) -> None` (raises `KeyError` if missing)
  - A todo is a dict: `{"id": int, "text": str, "done": bool, "created_at": "ISO8601"}`
- **API**:
  - `GET  /api/todos`      -> `{"todos": [...], "count": int}`
  - `POST /api/todos`      body `{"text": str}` -> created todo (201)
  - `PATCH /api/todos/{id}` body `{"done": bool}` or `{"text": str}` -> updated todo
  - `DELETE /api/todos/{id}` -> 204
  - `GET  /health`         -> `{"status": "ok"}`
- **Frontend**: served by FastAPI from `static/` (`/index.html`). Vanilla JS, no build step.
- **App entrypoint**: `uv run uvicorn app.main:app --reload`

## Working agreements

- Implement only what the ticket asks. Do not expand scope silently.
- Every change ships with tests in `tests/` (`pytest` + FastAPI `TestClient`).
- Run the full pipeline before committing and make it green:
  - `uv run ruff check app mcp_server tests scripts`
  - `uv run pytest -q`
- Commit in the **current branch** with a clear message starting with the ticket key
  (e.g. `T-3: Delete todo endpoint`). Never commit directly to `main`.
- Never touch Linear status or GitHub PRs yourself — the driver script owns those.
- Prefer small, focused diffs.

## Cross-session memory

Before starting any ticket read `docs/decisions.md` and `docs/memory.md`. After finishing
significant work, append a short entry to `docs/memory.md` (what changed, what you learned,
what's risky). Keep entries under ~10 lines.