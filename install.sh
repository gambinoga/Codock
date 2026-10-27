#!/bin/sh
set -eu
DOCK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "$(uname -s)" in
  Darwin)
    DOCK_APP="$DOCK_ROOT/Codex Dock.app"
    if [ ! -d "$DOCK_APP" ]; then
      if ! xcrun --find swiftc >/dev/null 2>&1; then
        echo 'Install Apple Command Line Tools with xcode-select --install, then retry.' >&2
        exit 1
      fi
      sh "$DOCK_ROOT/src/build.sh"
      DOCK_APP="$DOCK_ROOT/Cloches Projets.app"
    fi
    mkdir -p "$HOME/Applications"
    # Stage a complete bundle: never merge stale resources into an old version.
    DOCK_STAGE=$(mktemp -d "$HOME/Applications/.codex-dock-install.XXXXXX")
    trap 'rm -rf "$DOCK_STAGE"' EXIT
    /usr/bin/ditto "$DOCK_APP" "$DOCK_STAGE/Codex Dock.app"
    /usr/bin/codesign --verify --deep --strict "$DOCK_STAGE/Codex Dock.app"
    if [ -e "$HOME/Applications/Codex Dock.app" ]; then
      mv "$HOME/Applications/Codex Dock.app" "$DOCK_STAGE/previous.app"
    fi
    if ! mv "$DOCK_STAGE/Codex Dock.app" "$HOME/Applications/Codex Dock.app"; then
      if [ -d "$DOCK_STAGE/previous.app" ]; then mv "$DOCK_STAGE/previous.app" "$HOME/Applications/Codex Dock.app"; fi
      exit 1
    fi
    # Do not remove quarantine or change Gatekeeper/privacy permissions.
    echo 'Installed ~/Applications/Codex Dock.app. Open it in Finder to finish first launch.'
    ;;
  *) echo 'Codex Dock currently supports macOS only.' >&2; exit 1 ;;
esac
