<div align="center">
  <img src="assets/codex-dock.svg" width="88" alt="Codex Dock icon">
  <h1>Codex Dock</h1>
  <p>A small floating macOS dock for your local Codex projects.</p>
</div>

See what is running, finished, failed, or waiting for you without keeping Codex in the foreground.
An independent community project, not an official OpenAI application.

## Install on macOS

**No Python, Xcode, API key, or subscription to this project is required for a release build.**
You do need a working local Codex installation whose metadata uses the supported schema.

1. Download the ZIP for your Mac from **[the latest release](https://github.com/gambinoga/codex-dock/releases/latest)**:
   - **Apple Silicon** (M1/M2/M3/M4/…): `Codex-Dock-macOS-arm64.zip`.
   - **Intel**: `Codex-Dock-macOS-x86_64.zip`.
2. Quit any previous copy, then unzip it and move **Codex Dock.app** to `~/Applications` (create that folder if necessary), or `/Applications`.
3. Open it, choose your Codex projects or project folders, set their short aliases and colors, and save.

**macOS 13 or later.** These initial builds are ad-hoc signed, not Apple notarized.
macOS may block the first launch: follow [Apple's instructions for opening an app from an identified source](https://support.apple.com/en-us/102445), only if you trust this repository.
The installer never removes quarantine or changes Gatekeeper or privacy permissions.
An organization-managed Mac may require approval from its administrator.

The ZIP also contains an optional `install.sh`: run `sh install.sh` to copy the app into `~/Applications`.
The app runs locally; it does not upload your chats or ask for your OpenAI credentials.

**Linux and Windows are not supported in this version.**

## Use it

- Configure **one or more projects**, without a fixed maximum. Choose an alias (1–8 characters) and one of four reusable palettes. Scroll the dock when it exceeds the screen edge.
- Drag the pill or any avatar to move it. It snaps vertically to the left/right edge or horizontally to the top/bottom.
- Hover an avatar for a summary. Click to open the only actionable conversation; with several candidates, open the conversation list.
- The list groups active conversations and recent read results. Opening or dismissing a finished/failed result marks it read; requests for input remain until answered in Codex.
- Use **Notifs** in the macOS menu bar to show the dock, configure projects, restart or quit. The legacy menu label is retained in this first public release.
- **⌥⌘J** shows/hides the dock. Right-click for visibility modes. Auto-hide leaves a small edge tab; events reveal the dock for a few seconds.
- After quitting, reopen Codex Dock.app from Applications. Nothing is added to login items automatically.

| State | Appearance |
| --- | --- |
| Idle / already read | Faded avatar; fully opaque on hover |
| Running | Continuous spinning ring in the project's accent |
| Needs you | Amber badge |
| Failed, unread | Red badge |
| Done, unread | Green dot |

The highest priority determines the badge: input request → unread failure → running → unread completion.
A ring keeps spinning whenever **any** conversation is running, even with an input/error badge.
A number replaces the badge when several conversations share the highest-priority state.

## Permissions and privacy

The dock reads local **project and conversation metadata**, not chat bodies, from `~/.codex` (configurable).
It never writes to Codex's SQLite databases and never approves requests on your behalf.
No telemetry, API calls, accounts, updater daemon, automatic startup or hooks are enabled by installation.

Settings, acknowledgements, cache and reader diagnostics are stored in
`~/Library/Application Support/Notifs` (the name is retained for compatibility with previous local builds).
The app bundle belongs in Applications, not Documents, to avoid unnecessary macOS folder permission prompts.

Input-request detection can optionally use passive Codex hooks. This is **opt-in**, requires your own review and Codex trust approval, and does not bypass that approval. See [optional hooks](docs/HOOKS.md).

## Compatibility and troubleshooting

- Local Codex metadata is an **internal, version-dependent format**, not a stable public API. Currently supported: `state_5.sqlite`, `thread_history_1.sqlite`, and the `threads` / `thread_turns` schemas exercised by the tests. Remote-only chats are not included.
- Clicking uses the exact `codex://threads/<id>` deep link. A failed OS launch falls back to the project's new-chat composer without marking the original result read. A successful OS handoff cannot prove that Codex rendered the destination. [Official deep-link documentation](https://learn.chatgpt.com/docs/app/commands).
- **“Refresh delayed / Actualisation retardée”** means the local reader has failed continuously for at least 30 seconds. Brief failures are retried silently and the last good state is kept. Recurrent `unable to open database file` failures have been observed and their underlying cause remains unresolved; this release does not claim to fix them. Share sanitized reader diagnostics in an issue, never your databases or chat content.
- Some full-screen applications or Spaces may affect window ordering. This is not a native macOS notification replacement.
- If the global shortcut is already registered by another app, use the menu bar instead.
- If the app is running but its icon is not visible, macOS may have insufficient menu bar space. The floating edge tab remains available; opening the app again shows the dock.

[Report a bug](https://github.com/gambinoga/codex-dock/issues/new?template=bug_report.yml).

## Contribute

Fork → create a branch → make changes → open a pull request. **The maintainer controls merges**;
contributors do not need or receive write access. Automatic merging is disabled.

Start with [CONTRIBUTING.md](CONTRIBUTING.md) for build commands, tests and architecture.
See [SECURITY.md](SECURITY.md) for reporting a private security issue.

## License

[MIT](LICENSE) for this project's code. The release reader includes Python and SQLite;
see [THIRD_PARTY.md](THIRD_PARTY.md). Codex itself is not included.
