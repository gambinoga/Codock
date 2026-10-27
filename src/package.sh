#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$TASK_ROOT/releases"
TASK_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/notifs-package.XXXXXX")
trap 'rm -rf "$TASK_STAGE"' EXIT
mkdir -p "$TASK_STAGE/Notifs"
cp -R "$TASK_ROOT/Cloches Projets.app" "$TASK_STAGE/Notifs/"
cp "$TASK_ROOT/LIRE-MOI.txt" "$TASK_STAGE/Notifs/"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$TASK_STAGE/Notifs" "$TASK_ROOT/releases/Notifs-macOS.zip"
printf '%s\n' "$TASK_ROOT/releases/Notifs-macOS.zip"
