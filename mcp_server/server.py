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
def explain_source(topic: str) -> dict:
    """Explain a feature by citing the real code that implements it.

    Examples: "win check", "where is state stored", "delete a todo", "PATCH", "done toggle".
    """
    roots = [ROOT / "app", ROOT / "mcp_server"]
    hits = []
    topic_l = topic.lower()
    for root in roots:
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
    return {
        "topic": topic,
        "matches": hits[:30],
        "hint": "Read app/storage.py and app/main.py for the authoritative flow.",
    }


if __name__ == "__main__":
    mcp.run()
