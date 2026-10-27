#!/usr/bin/env python3
"""Passive observer: never approves, denies, modifies, or adds model context."""
import fcntl
from contextlib import ExitStack
import json
import os
from pathlib import Path
import sys
import time
import sqlite3


def atomic_write(path, value):
    temp = path.with_name(path.name + "." + str(os.getpid()) + ".tmp")
    temp.write_text(json.dumps(value))
    os.replace(temp, path)


def observe(payload, data, home=None):
    thread = payload.get("session_id")
    turn = payload.get("turn_id")
    if not thread:
        return
    # Legacy trusted hook commands keep their exact command and trust record.
    # Resolve their data migration only after locking, so an in-flight hook cannot
    # write back into the old folder after the installer has redirected it.
    data.mkdir(parents=True, exist_ok=True)
    with ExitStack() as stack:
        lock = stack.enter_context((data / "hook.lock").open("a"))
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            redirect = json.loads((data / "data-redirect.json").read_text())
        except (OSError, ValueError):
            redirect = {}
        support = Path.home() / "Library/Application Support/Notifs"
        if redirect.get("data") == str(support) and data != support:
            data = support
            data.mkdir(parents=True, exist_ok=True)
            target_lock = stack.enter_context((data / "hook.lock").open("a"))
            fcntl.flock(target_lock, fcntl.LOCK_EX)
        if home is None:
            try:
                config = json.loads((data / "configuration.json").read_text())
            except (OSError, ValueError):
                config = {}
            home = Path(config["codexHome"]).expanduser() if config.get("codexHome") else Path.home() / ".codex"
        # Child hooks may carry the parent's session_id. Match its actual turn.
        if turn:
            try:
                with sqlite3.connect((home / "thread_history_1.sqlite").resolve().as_uri() + "?mode=ro", uri=True, timeout=0.2) as db:
                    if not db.execute("SELECT 1 FROM thread_turns WHERE thread_id=? AND turn_id=? LIMIT 1", (thread, turn)).fetchone():
                        return
            except sqlite3.Error:
                return
        event = payload.get("hook_event_name")
        tool = payload.get("tool_name", "")
        call = payload.get("tool_use_id") or payload.get("tool_call_id")
        # Metadata only. Do not persist tool inputs, prompts or answers.
        try:
            state = json.loads((data / "waiting.json").read_text())
        except (OSError, ValueError):
            state = {}
        current = state.get(thread, {"turn": turn, "pending": {}})
        if turn and current.get("turn") != turn:
            current = {"turn": turn, "pending": {}}
        pending = current.setdefault("pending", {})
        was_waiting = "input" in pending.values()
        now = time.time()
        if event in ("UserPromptSubmit", "Interrupt", "SessionEnd"):
            current = {"turn": turn, "pending": {}}
        # PermissionRequest includes automatic policy reviews. It does not
        # establish that the human is being asked to answer.
        elif event == "PreToolUse" and ("request_user_input" in tool or "request_permissions" in tool):
            # Async UI questions return immediately; do not claim they block execution.
            if "async" not in tool:
                pending[call or tool] = "input"
        elif event == "PostToolUse":
            pending.pop(call or tool, None)
            # PermissionRequest can omit the call ID while PostToolUse supplies it.
            # Remove only this tool fallback, preserving other keyed requests.
            if tool:
                pending.pop(tool, None)
        if "input" in current.get("pending", {}).values():
            if not was_waiting:
                current["inputSince"] = now
        else:
            current.pop("inputSince", None)
        current["updated"] = now
        state[thread] = current
        state = {k: v for k, v in state.items() if v.get("updated", 0) > time.time() - 7 * 86400}
        atomic_write(data / "waiting.json", state)
        atomic_write(data / "hook-seen.json", {"at": time.time()})


if __name__ == "__main__":
    try:
        observe(json.load(sys.stdin), Path(sys.argv[1]), Path(sys.argv[2]) if len(sys.argv) > 2 else None)
    except Exception:
        # An optional status display must never interfere with an agent's execution.
        pass
    # Stop/Interrupt and similar hooks expect either empty output or JSON, never prose.
    print("{}")
