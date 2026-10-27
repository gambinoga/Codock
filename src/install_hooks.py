#!/usr/bin/env python3
"""Merge passive hooks; never write or bypass Codex's trust records."""
import argparse
import datetime
import json
from pathlib import Path
import shlex

DESCRIPTION = "Codock: passive status observation"


def merged_hooks(existing, root, app=None, data=None, home=None):
    app = app or root / "Codock.app"
    data = data or root / "Data"
    resources = app / "Contents" / "Resources"
    command = "/usr/bin/python3 " + shlex.quote(str(resources / "hook.py")) + " " + shlex.quote(str(data))
    if home is not None and home != Path.home() / ".codex":
        command += " " + shlex.quote(str(home))
    hooks = existing.setdefault("hooks", {})
    for event in ["UserPromptSubmit", "PermissionRequest", "PreToolUse", "PostToolUse", "Interrupt", "SessionEnd"]:
        groups = hooks.setdefault(event, [])
        # Replace only our exact command; keep unrelated user hooks untouched.
        groups[:] = [g for g in groups if not any(h.get("command") == command for h in g.get("hooks", []))]
        matcher = ".*request_user_input.*|.*request_permissions.*" if event == "PreToolUse" else "*"
        groups.append({"matcher": matcher, "hooks": [{"type": "command", "command": command, "timeout": 3}]})
    existing.setdefault("description", DESCRIPTION)
    return existing


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--app", type=Path)
    parser.add_argument("--data", type=Path)
    parser.add_argument("--home", type=Path, default=Path.home() / ".codex")
    args = parser.parse_args()
    source = Path(__file__).resolve()
    app = args.app or (source.parents[2] if source.parent.name == "Resources" else source.parents[1] / "Codock.app")
    root = app.parent
    data = args.data or Path.home() / "Library/Application Support/Notifs"
    data.mkdir(parents=True, exist_ok=True)
    target = args.home / "hooks.json"
    original = target.read_text() if target.exists() else None
    content = json.loads(original) if original else {}
    merged = json.dumps(merged_hooks(content, root, app, data, args.home), indent=2, ensure_ascii=False) + "\n"
    (data / "prepared-hooks.json").write_text(merged)
    if args.install:
        if original is not None:
            stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
            (data / ("hooks-backup-" + stamp + ".json")).write_text(original)
        target.write_text(merged)
        print("Hooks installed. Review and explicitly approve trust with /hooks in Codex.")
    else:
        print(data / "prepared-hooks.json")


if __name__ == "__main__":
    main()
