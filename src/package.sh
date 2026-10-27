#!/bin/sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$TASK_ROOT/releases"
TASK_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/notifs-package.XXXXXX")
trap 'rm -rf "$TASK_STAGE"' EXIT
mkdir -p "$TASK_STAGE/Codock"
cp -R "$TASK_ROOT/Codock.app" "$TASK_STAGE/Codock/"
cp "$TASK_ROOT/USER_GUIDE.txt" "$TASK_STAGE/Codock/"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$TASK_STAGE/Codock" "$TASK_ROOT/releases/Codock-macOS.zip"
printf '%s\n' "$TASK_ROOT/releases/Codock-macOS.zip"
