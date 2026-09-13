#!/usr/bin/env python3
"""MCP server exposing the Shayan Todo app to LLM clients.

Connect with Claude Code (.mcp.json) or Codex
(codex mcp add shayan-todo -- uv run mcp_server/server.py),
then ask questions like "what does the win check do?" or "where is state stored?" — the tools
return live state from data/todos.json and cite the real source code.

Run: uv run mcp_server/server.py   (stdio transport by default)
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from mcp.server.mcpserver import MCPServer  # noqa: E402

mcp = MCPServer("shayan-todo")

TEXT_SUFFIXES = {".py", ".js", ".html", ".css", ".json"}
IGNORE_PARTS = {".git", ".venv", "node_modules", "__pycache__", "data", "docs", "static"}
SOURCE_ROOTS = [ROOT / "app", ROOT / "mcp_server"]


def _storage():
    from app import storage  # created by the agent loop; contract in CLAUDE.md

    return storage


@mcp.tool()
def get_todos() -> dict:
    """Return the current list of todos (live state) plus a count."""
    try:
        todos = _storage().list_todos()
    except Exception as e:  # storage not built yet — honest failure, no fake data
        return {"todos": [], "count": 0, "error": str(e)}
    return {"todos": todos, "count": len(todos)}


@mcp.tool()
def get_todo(todo_id: int) -> dict:
    """Return a single todo by its numeric id."""
    try:
        for t in _storage().list_todos():
            if t["id"] == todo_id:
                return {"todo": t}
        return {"error": f"todo {todo_id} not found"}
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def todo_stats() -> dict:
    """Return aggregate counts: total, done, open."""
    try:
        todos = _storage().list_todos()
        return {
            "total": len(todos),
            "done": sum(1 for t in todos if t.get("done")),
            "open": sum(1 for t in todos if not t.get("done")),
        }
    except Exception as e:
        return {"total": 0, "done": 0, "open": 0, "error": str(e)}


@mcp.tool()
def add_todo(text: str) -> dict:
    """Add a todo with the given text; returns the created todo."""
    try:
        return {"todo": _storage().add_todo(text)}
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
def app_info() -> dict:
    """Return a concise, truthful description of the app: what it is, the stack, and
    exactly where each concern lives (state, API, frontend). Use this for questions like
    'where is state stored?' when you want the authoritative structure.
    """
    return {
        "name": "shayan-todo",
        "kind": "Todo list (add, complete, delete, persist)",
        "backend": "FastAPI (app/main.py) served with uvicorn",
        "state": "persisted to data/todos.json via app/storage.py (functions: "
        "list_todos, add_todo, update_todo, delete_todo). Todos are dicts: "
        "{id:int, text:str, done:bool, created_at:ISO8601}.",
        "api": [
            "GET /api/todos -> {todos, count}",
            "POST /api/todos {text} -> todo (201)",
            "PATCH /api/todos/{id} {done|text} -> todo",
            "DELETE /api/todos/{id} -> 204",
            "GET /health -> {status:ok}",
        ],
        "frontend": "static/index.html + vanilla JS + CSS, served from /",
        "not_a_tic_tac_toe": True,
        "hint": "Ask explain_source('state') or explain_source('delete') for actual code.",
    }


@mcp.tool()
def explain_source(topic: str) -> dict:
    """Explain a feature by citing the real code that implements it.

    Examples: "where is state stored", "add a todo", "delete a todo", "PATCH", "done toggle",
    "win check" (returns an honest 'not applicable' for this todo app).
    """
    hits = _search_source(topic)
    if hits:
        return {
            "topic": topic,
            "matches": hits[:30],
            "hint": "Read app/storage.py and app/main.py for the authoritative flow.",
        }
    low = topic.lower()
    if "win" in low or "tic tac" in low or "game" in low:
        return {
            "topic": topic,
            "not_found": True,
            "explanation": (
                "This repo is a Todo list app, not a Tic Tac Toe game, so there is no "
                "win check in the codebase. The closest feature is the 'done' toggle "
                "(PATCH /api/todos/{id} with {\"done\": bool}) and delete. "
                "See app_info() for the full structure."
            ),
        }
    return {
        "topic": topic,
        "not_found": True,
        "explanation": (
            f"No code matched '{topic}'. This is a Todo app (FastAPI backend, storage in "
            "data/todos.json). Try topics like: state, storage, add, delete, complete, "
            "done toggle, PATCH, health, frontend. app_info() lists everything."
        ),
    }


def _search_source(topic: str) -> list[dict]:
    hits = []
    topic_l = topic.lower()
    for root in SOURCE_ROOTS:
        for path in sorted(root.rglob("*")):
            if path.suffix not in TEXT_SUFFIXES:
                continue
            if any(part in IGNORE_PARTS for part in path.parts):
                continue
            try:
                lines = path.read_text().splitlines()
            except Exception:
                continue
            for i, line in enumerate(lines, 1):
                if not topic_l or topic_l in line.lower():
                    hits.append(
                        {"file": str(path.relative_to(ROOT)), "line": i, "code": line.strip()}
                    )
    return hits


if __name__ == "__main__":
    mcp.run()
