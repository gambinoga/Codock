#!/usr/bin/env python3
"""Install the built application outside protected Documents, preserving user data.

Does not grant permissions, change hooks definitions, or modify any TCC database.
"""
import argparse
import datetime
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

DATA_FILES = ("state.json", "configuration.json", "last-snapshot.json", "waiting.json", "hook-seen.json", "reader-errors.json")


def migrate_data(legacy, support):
    support.mkdir(parents=True, exist_ok=True)
    if not legacy.exists() or legacy == support:
        return
    with (legacy / "hook.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        # Existing current data always wins. Never reset acknowledgements/settings.
        for name in DATA_FILES:
            source, target = legacy / name, support / name
            if source.is_file() and not target.exists():
                temp = support / (name + ".migration.tmp")
                shutil.copyfile(source, temp)
                os.replace(temp, target)
        marker = legacy / "data-redirect.json"
        temp = marker.with_suffix(".tmp")
        temp.write_text(json.dumps({"data": str(support)}))
        os.replace(temp, marker)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--install", action="store_true", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    source = root / "Cloches Projets.app"
    apps = Path.home() / "Applications"
    support = Path.home() / "Library/Application Support/Notifs"
    destination = apps / source.name
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(source)], check=True)
    apps.mkdir(parents=True, exist_ok=True)
    migrate_data(root / "Data", support)
    with tempfile.TemporaryDirectory(prefix=".notifs-install-", dir=apps) as temporary:
        staged = Path(temporary) / source.name
        shutil.copytree(source, staged, symlinks=True)
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(staged)], check=True)
        if destination.exists():
            backups = support / "installation-backups"
            backups.mkdir(exist_ok=True)
            stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
            subprocess.run(["/usr/bin/ditto", "-c", "-k", "--keepParent", str(destination), str(backups / (stamp + ".zip"))], check=True)
            previous = Path(temporary) / "previous.app"
            os.replace(destination, previous)
            try:
                os.replace(staged, destination)
            except OSError:
                os.replace(previous, destination)
                raise
        else:
            os.replace(staged, destination)
    print(json.dumps({"application": str(destination), "data": str(support)}))


if __name__ == "__main__":
    main()
