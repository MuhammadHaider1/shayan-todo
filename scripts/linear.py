#!/usr/bin/env python3
"""Linear helper for the agent loop. REST v1, stdlib only.

Subcommands:
  seed        create the Shayan Todo project + tickets (idempotent)
  next        print the next Backlog ticket as JSON: id, identifier, title, description
  set-state <id> <StateName>   move a ticket to a workflow state (e.g. "In Progress", "Done")

Env: LINEAR_API_KEY (required), LINEAR_API_URL (default https://api.linear.app)
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

API = os.environ.get("LINEAR_API_URL", "https://api.linear.app").rstrip("/")
KEY = os.environ.get("LINEAR_API_KEY", "")

PROJECT_NAME = "Shayan Todo (Agent Loop)"

TICKETS = [
    {
        "title": "Scaffold FastAPI todo API (GET/POST /api/todos) + storage + tests",
        "description": (
            "Create the FastAPI app under app/. Add app/storage.py with the exact "
            "interface contract from CLAUDE.md (data/todos.json), Pydantic model for a todo, "
            "GET /api/todos returning {\"todos\": [...], \"count\": n} with a fake seed of a "
            "couple of todos, POST /api/todos (text) returning the created todo, plus "
            "GET /health. Mount the static/ dir. Write pytest tests covering list + add + "
            "health. Leave the frontend for a later ticket (index.html can be a stub)."
        ),
        "priority": 1,
    },
    {
        "title": "Complete a todo: PATCH /api/todos/{id} (toggle done)",
        "description": (
            "Implement PATCH /api/todos/{id} accepting {\"done\": bool} or {\"text\": str} and "
            "returning the updated todo. 404 when the id is unknown. Extend storage.update_todo. "
            "Add tests for toggling, renaming, and 404s. Keep the CLAUDE.md contract."
        ),
        "priority": 2,
    },
    {
        "title": "Delete a todo: DELETE /api/todos/{id}",
        "description": (
            "Implement DELETE /api/todos/{id} -> 204, 404 when missing. Add storage.delete_todo "
            "and tests (delete existing, delete missing, list after delete). Keep contract."
        ),
        "priority": 2,
    },
    {
        "title": "Frontend: add + list todos (vanilla JS)",
        "description": (
            "Build static/index.html + static/index.js + static/style.css served from /index.html. "
            "Load todos from GET /api/todos, render them, and add new ones via POST. Minimal but "
            "clean styling. Tests are not required for the frontend itself."
        ),
        "priority": 2,
    },
    {
        "title": "Frontend: toggle done, delete, and an empty state",
        "description": (
            "Wire a checkbox to PATCH done on each rendered todo and a delete button to "
            "DELETE. Show a friendly empty state when there are no todos. Keep styles tidy."
        ),
        "priority": 3,
    },
    {
        "title": "Bug: todo text is rendered unsafely (HTML injection in the list)",
        "description": (
            "Todos are currently inserted into the DOM with innerHTML, so text like "
            "<img src=x onerror=alert(1)> renders/executes. Fix by using textContent / a "
            "DOM-building approach so all todo text renders literally. Add a regression "
            "test for list_todos round-tripping exactly what was added."
        ),
        "priority": 2,
    },
]


def req(method: str, path: str, payload=None):
    if not KEY:
        sys.exit(
            "ERROR: LINEAR_API_KEY is not set.\nCreate a personal API key at "
            "linear.app > Settings > API, then export LINEAR_API_KEY=<key>."
        )
    body = json.dumps(payload).encode() if payload is not None else None
    r = urllib.request.Request(
        API + path,
        data=body,
        method=method,
        headers={"Authorization": KEY, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(r) as resp:  # noqa: S310 (linear API is trusted)
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} on {method} {path}: {e.read().decode()[:400]}", file=sys.stderr)
        sys.exit(1)


def get_team() -> dict:
    teams = req("GET", "/api/v1/teams").get("data", [])
    if not teams:
        sys.exit("No Linear team found — create one first.")
    return teams[0]


def states_by_name(team_id: str) -> dict[str, str]:
    raw = req("GET", f"/api/v1/workflow-states?teamId={team_id}").get("data", [])
    return {s["name"].lower(): s["id"] for s in raw}


def state_id(team_id: str, name: str) -> str:
    by_name = states_by_name(team_id)
    sid = by_name.get(name.lower())
    if not sid:
        sys.exit(f"workflow state '{name}' not found for team. Available: {sorted(by_name)}")
    return sid


def issue_by_title(team_id: str, title: str) -> dict | None:
    issues = req("GET", f"/api/v1/issues?teamId={team_id}&first=200").get("data", [])
    for issue in issues:
        if issue.get("title") == title:
            return issue
    return None


def all_issues(team_id: str) -> list[dict]:
    return req("GET", f"/api/v1/issues?teamId={team_id}&first=200").get("data", [])


def team_issue_state_map(team_id: str) -> dict[str, str]:
    by_name = states_by_name(team_id)
    return {v: name for name, v in by_name.items()}  # stateId -> name


def cmd_seed() -> None:
    team = get_team()
    tid, tkey = team["id"], team["key"]
    proj = next(
        (
            p
            for p in req("GET", "/api/v1/projects").get("data", [])
            if p.get("name") == PROJECT_NAME
        ),
        None,
    )
    if not proj:
        proj = req(
            "POST",
            "/api/v1/projects",
            {"name": PROJECT_NAME, "teamIds": [tid]},
        ).get("data", {})
        print(f"created project {proj.get('id')}")
    backlog = state_id(tid, "Backlog")
    for t in TICKETS:
        if issue_by_title(tid, t["title"]):
            print(f"skip   {t['title']}")
            continue
        created = req(
            "POST",
            "/api/v1/issues",
            {
                "title": t["title"],
                "description": t["description"],
                "teamId": tid,
                "projectId": proj["id"],
                "stateId": backlog,
                "priority": t["priority"],
            },
        ).get("data", {})
        print(f"created {created.get('identifier')}  {created.get('url')}")
    print(f"team key: {tkey}  | project: {PROJECT_NAME}  | https://linear.app")


def cmd_next() -> None:
    team = get_team()
    tid = team["id"]
    backlog_id = state_id(tid, "Backlog")
    issues = [i for i in all_issues(tid) if i.get("stateId") == backlog_id]
    issues.sort(key=lambda i: i.get("createdAt", ""))
    if not issues:
        print("NO_TICKET")
        sys.exit(2)
    t = issues[0]
    print(
        json.dumps(
            {
                "id": t["id"],
                "identifier": t["identifier"],
                "title": t["title"],
                "description": t.get("description") or "",
            }
        )
    )


def cmd_set_state(aid: str, name: str) -> None:
    team = get_team()
    tid = team["id"]
    req("PATCH", f"/api/v1/issues/{aid}", {"stateId": state_id(tid, name)})
    print(f"set {aid} -> {name}")


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "seed":
        cmd_seed()
    elif cmd == "next":
        cmd_next()
    elif cmd == "set-state" and len(args) == 2:
        cmd_set_state(args[0], args[1])
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
