# Contributing to Codex Dock

Bug reports, documentation and focused pull requests are welcome. The maintainer is
[@gambinoga](https://github.com/gambinoga). Contributors work through forks; the maintainer
reviews and merges. Do not enable auto-merge, merge somebody else's PR, or request repository write access just to contribute.

## Development requirements

- macOS 13+, Apple Command Line Tools (`xcode-select --install`).
- Swift (provided by those tools).
- Python 3.10+ for reader tests and release packaging. Ordinary release users do not need Python.
- Git; a GitHub account is needed only to submit a PR.

```sh
git clone https://github.com/YOUR-LOGIN/codex-dock.git
cd codex-dock
git switch -c fix/short-description
sh src/build.sh
'Cloches Projets.app/Contents/MacOS/ProjectBells' --self-test
python3 src/test_backend.py
```

The development bundle keeps its legacy filename `Cloches Projets.app` and executable
`ProjectBells` so existing local hook commands remain valid. Release packaging renames
the bundle to Codex Dock.app; it does not change the executable or bundle identifier.

To test the development app, copy it to Applications before launching it. The dock
must stay outside protected Documents/Downloads folders during runtime. Development
and release builds share the same `Application Support/Notifs` data: back it up if
experimenting with configuration/state formats, and run only one copy at a time.
`src/install_local.py --install` is the original developer installer; it preserves
legacy data and installs `~/Applications/Cloches Projets.app`, not the public release name.

## Architecture

- `src/ProjectBells.swift`: task model, notifications, persistence and external navigation.
- `src/StatusDock.swift`: AppKit windows, menu bar, hit testing, snapping and drag lifecycle.
- `src/LoadingRingView.swift`: compositor-driven loading animation shared by dock/list.
- `src/ThreadPresentation.swift`, `src/ConversationPanel.swift`: summaries and list layout.
- `src/ProjectSettings.swift`, `src/DockConfiguration.swift`: project configuration.
- `src/backend.py`: read-only metadata adapter, launched out of process.
- `src/hook.py`, `src/install_hooks.py`: optional passive hooks; never approve or alter trust.
- `src/ModelTests.swift`, `src/DockTests.swift`, `src/test_backend.py`: executable checks and synthetic fixtures.

Do not read chat bodies to infer states, traverse unrelated project directories,
write Codex databases, grant privacy permissions, or modify trust records. Preserve
read/unread state, exact-thread navigation, multi-project aggregation and the native UI.
Internal SQLite schemas can change; keep compatibility assumptions explicit and tested.

## Release builds

CI tests Intel and Apple Silicon separately. A tagged release builds an isolated
Python reader, embeds it in the app, verifies its synthetic fixture output and signature,
and generates per-architecture ZIPs with checksums. No developer data is packaged.

Locally, with Python 3.10+:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-release.txt
.venv/bin/PYINSTALLER_CONFIG_DIR="$PWD/build/pyinstaller-cache" python -m PyInstaller --clean --noconfirm --onefile --name reader --distpath build/reader-dist --workpath build/reader-work --specpath build src/backend.py
DOCK_BUNDLED_READER="$PWD/build/reader-dist/reader" sh src/build.sh
DOCK_READER_BINARY="$PWD/build/reader-dist/reader" .venv/bin/python src/test_backend.py
'Cloches Projets.app/Contents/MacOS/ProjectBells' --self-test
.venv/bin/python scripts/package_release.py
```

Release publishing is a maintainer action: create/push a `v*` tag. PR workflows have
read-only permissions; only the release publishing job receives `contents: write`.
No notarization credentials are configured. Do not claim a notarized release without
adding and verifying an authorized Apple signing/notarization process.

## Pull request checklist

Describe the problem, behavior change and actual validation. Add a focused regression
check when it prevents a meaningful bug; do not add tests that merely mirror implementation.
For visual changes include screenshots with synthetic projects and no private chat titles.
Never commit `Data/`, local paths, credentials, databases, logs, configuration or hook trust.
Keep PRs focused. Report uncertainties honestly, especially physical drag, full-screen,
Space, shortcut, installation and real Codex deep-link behavior not covered by unit checks.
