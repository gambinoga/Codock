Codock v2.3.0 — English interface and synchronized docks for macOS 13+.

- Renamed the application and downloadable bundles to Codock.
- English menus, settings, statuses, tooltips, accessibility labels and help.
- Icon-only menu bar control.
- Twelve project palettes and native custom accent/background color pickers.
- Independent whole-dock background color.
- Duplicate dock creates synchronized copies with independent display, position,
  visibility and selection; all share the same reader and read/unread state.
- Existing settings, notifications, colors, cloned positions and trusted hook
  commands remain compatible; the internal legacy data directory is retained.

Separate Apple Silicon and Intel packages contain the standalone local reader.
No Python or developer tools are needed for normal installation. Builds are ad-hoc
signed, not Apple notarized; follow the README for first launch.

Known limitation: local metadata can intermittently fail with unable to open database
file. Last known state is kept and prolonged failures are shown. Internal Codex schemas
can change. Physical drag, Spaces, full-screen and real deep links need manual testing.

Contribute through forks and PRs. The maintainer controls merges; auto-merge is disabled.
