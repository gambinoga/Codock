#!/usr/bin/env python3
"""Read Codex metadata without writing to its databases or reading chat bodies."""
import argparse
import json
import os
from pathlib import Path
import sqlite3
import sys
import time



def read_json(path, fallback):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return fallback


def project_for(thread, global_state, projects):
    # Explicit membership takes precedence over the current directory (worktrees).
    assigned = global_state.get("thread-project-assignments", {}).get(thread["id"])
    if isinstance(assigned, dict):
        assigned = assigned.get("projectId")
    identity = thread.get("project_id") or assigned
    for p in projects:
        if identity and identity == p["id"]:
            return p["name"]
    # Metadata comparison must never stat or traverse project folders, including
    # unrelated Documents/Desktop paths that would trigger macOS privacy prompts.
    cwd = os.path.normpath(thread["cwd"])
    matches = [(len(os.path.normpath(root)), p["name"]) for p in projects if not identity or not p["id"] for root in p["roots"]
               if cwd == os.path.normpath(root) or cwd.startswith(os.path.normpath(root) + os.sep)]
    if matches:
        return max(matches)[1]
    return None


def catalog_from(state):
    return [{"id": identity, "name": project.get("name") or "Project", "roots": project.get("rootPaths") or []}
            for identity, project in state.get("local-projects", {}).items()
            if isinstance(project, dict) and project.get("rootPaths")]


def projects_from(state, configuration):
    catalog = {p["id"]: p for p in catalog_from(state)}
    result = []
    for project in configuration.get("projects", []):
        identity = project.get("codexID")
        # Stable local key is independent of the displayed alias.
        result.append({"id": identity, "name": project["id"],
                       "roots": catalog.get(identity, {}).get("roots") or project.get("roots") or []})
    return result


def snapshot(home, data_dir):
    global_state = read_json(home / ".codex-global-state.json", {})
    configuration = read_json(data_dir / "configuration.json", {"projects": []})
    projects = projects_from(global_state, configuration)
    # URI mode=ro includes live WAL changes; immutable=1 would hide active updates.
    connection = sqlite3.connect((home / "state_5.sqlite").as_uri() + "?mode=ro", uri=True, timeout=1)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA query_only=ON")
    try:
        connection.execute("ATTACH DATABASE ? AS history", ((home / "thread_history_1.sqlite").as_uri() + "?mode=ro",))
        archived_ids = [row[0] for row in connection.execute("SELECT id FROM threads WHERE archived=1")]
        rows = connection.execute("""
            SELECT t.id, t.cwd, t.name, t.project_id, t.source,
                   u.turn_id, u.status, u.started_at, u.completed_at
            FROM threads t LEFT JOIN history.thread_turns u
              ON u.thread_id=t.id AND u.turn_id=(
                SELECT v.turn_id FROM history.thread_turns v
                WHERE v.thread_id=t.id ORDER BY v.rollout_ordinal DESC LIMIT 1)
            WHERE t.archived=0 AND t.source NOT LIKE '%subagent%'
            ORDER BY t.updated_at DESC
        """).fetchall()
    finally:
        connection.close()
    waiting = read_json(data_dir / "waiting.json", {})
    tasks = []
    for row in rows:
        thread = dict(row)
        project = project_for(thread, global_state, projects)
        if not project or not thread["turn_id"]:
            continue
        # Historical crashed sessions can retain inProgress forever. A missing
        # writer-lock file proves this session is not loaded on this host.
        if thread["status"] == "inProgress" and not (home / "thread-writer-locks" / (thread["id"] + ".lock")).exists():
            thread["status"] = "notLoaded"
        pending = waiting.get(thread["id"], {})
        awaiting = (thread["status"] == "inProgress" and
                    pending.get("turn") == thread["turn_id"] and
                    "input" in pending.get("pending", {}).values())
        title = global_state.get("thread-titles", {}).get("titles", {}).get(thread["id"])
        if not isinstance(title, str):
            title = thread.get("name") or "Conversation"
        tasks.append({"id": thread["id"], "project": project,
                      "title": title[:180],
                      "turn": thread["turn_id"], "status": "waiting" if awaiting else thread["status"],
                      "started": thread["started_at"] or 0, "completed": thread["completed_at"] or 0,
                      "stateChanged": pending.get("inputSince", thread["started_at"] or 0) if awaiting else (thread["completed_at"] or thread["started_at"] or 0)})
    tasks.sort(key=lambda task: (task["project"], task["started"], task["id"]))
    return {"connected": True, "tasks": tasks, "projects": projects, "availableProjects": catalog_from(global_state), "archivedIDs": archived_ids,
            "inputMonitoring": (data_dir / "hook-seen.json").exists(), "timestamp": time.time()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--home", type=Path, default=Path.home() / ".codex")
    parser.add_argument("--data", type=Path, required=True)
    args = parser.parse_args()
    home = args.home.resolve()
    data = args.data.resolve()
    read_errors = []
    for attempt in range(3):
        try:
            result = snapshot(home, data)
            break
        except (OSError, sqlite3.Error, KeyError) as exc:
            read_errors.append({"error": str(exc), "sqliteCode": getattr(exc, "sqlite_errorcode", None),
                                "sqliteName": getattr(exc, "sqlite_errorname", None)})
            result = {"connected": False, "tasks": [], "projects": [],
                      "inputMonitoring": False, "error": str(exc), "timestamp": time.time()}
            if attempt < 2:
                time.sleep(0.15)
    # Local reader diagnostics contain paths and read status only, never chat bodies.
    try:
        status = {k: result.get(k) for k in ("connected", "error", "timestamp")}
        status["sourceHome"] = str(home)
        temp = data / ("reader-status." + str(os.getpid()) + ".tmp")
        temp.write_text(json.dumps(status))
        os.replace(temp, data / "reader-status.json")
        if read_errors:
            history = read_json(data / "reader-errors.json", [])
            databases = {}
            for name in ("state_5.sqlite", "thread_history_1.sqlite"):
                path = home / name
                databases[name] = {"exists": path.exists(), "readable": os.access(path, os.R_OK)}
            history.append({"at": time.time(), "recovered": result["connected"], "sourceHome": str(home),
                            "attempts": read_errors, "databases": databases})
            temp = data / ("reader-errors." + str(os.getpid()) + ".tmp")
            temp.write_text(json.dumps(history[-100:]))
            os.replace(temp, data / "reader-errors.json")
    except OSError:
        pass
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
