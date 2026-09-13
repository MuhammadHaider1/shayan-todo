#!/usr/bin/env python3
"""MCP stdio self-test — proves mcp_server/server.py speaks the MCP protocol over stdio,
so any MCP client (Codex, Claude Code, Gemini CLI) can connect, list tools, and call them.

Speaks raw JSON-RPC (initialize -> initialized -> tools/list -> tools/call) to the server,
exactly the way Claude Code and Codex do under the hood.

Usage:  uv run python scripts/mcp_selftest.py
"""
from __future__ import annotations

import json
import os
import queue
import subprocess
import sys
import threading

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER = ["uv", "run", "mcp_server/server.py"]


def main() -> None:
    proc = subprocess.Popen(
        SERVER,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        cwd=ROOT,
    )
    lines: queue.Queue = queue.Queue()

    def pump() -> None:
        for line in proc.stdout:
            lines.put(line)

    threading.Thread(target=pump, daemon=True).start()

    def send(msg: dict) -> None:
        proc.stdin.write(json.dumps(msg) + "\n")
        proc.stdin.flush()

    def recv(timeout: float = 20) -> dict:
        try:
            line = None
            deadline = timeout
            while deadline > 0:
                line = lines.get(timeout=deadline)
                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    deadline -= 0.5
                    continue
                return msg
            raise TimeoutError("MCP server did not respond")
        except queue.Empty:
            raise TimeoutError("MCP server did not respond")

    print("== MCP stdio handshake ==")
    send(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-03-26",
                "capabilities": {},
                "clientInfo": {"name": "selftest", "version": "1.0"},
            },
        }
    )
    init = recv()
    assert init.get("id") == 1, init
    print("initialize ->", json.dumps(init.get("result", {}))[:200])

    send({"jsonrpc": "2.0", "method": "notifications/initialized"})
    print("initialized notification sent")

    send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
    tools = recv()
    assert tools.get("id") == 2, tools
    names = [t["name"] for t in tools.get("result", {}).get("tools", [])]
    print("tools/list  ->", ", ".join(names))

    calls = [
        ("app_info", {}),
        ("get_todos", {}),
        ("explain_source", {"topic": "win check"}),
    ]
    for tool, args in calls:
        send(
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {"name": tool, "arguments": args},
            }
        )
        result = recv()
        content = result.get("result", {}).get("content", [])
        text = "".join(c.get("text", "") for c in content)
        print(f"call {tool:<16} -> {text[:150]!r}")

    proc.terminate()
    print("== MCP self-test PASSED ==")


if __name__ == "__main__":
    sys.exit(main())
