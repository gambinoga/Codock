Initial public release of Codex Dock for macOS 13+.

- Native floating dock with configurable project aliases and colors.
- One or more projects, with no fixed maximum; overflow scrolls.
- Running, needs-input, failed and unread completion states.
- Continuous loading animation, recent conversations and acknowledgement.
- Menu bar controls, edge snapping and automatic visibility.
- Separate Apple Silicon and Intel packages with a bundled local reader: no Python or developer tools required for normal installation.

Download the ZIP for your architecture and move Codex Dock.app into Applications.
These builds are ad-hoc signed, not notarized; follow the README for first launch.
No user settings, history, databases, credentials or hook approvals are packaged.

Known limitation: local metadata reads can intermittently fail with `unable to open database file`.
The last known state is kept and prolonged failures are shown. Internal Codex database
schemas may change. Physical drag, Spaces, full-screen, real deep links and shortcut
behavior need manual testing on your desktop; automated tests do not prove those flows.

Contribute through forks and pull requests. Maintainer controls merges; auto-merge is disabled.
