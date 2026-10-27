# Optional input-request hooks

Running, finished and failed states use local metadata without installing hooks.
Explicit blocking questions can optionally be observed with passive Codex hooks.
Automatic policy reviews are not presented as requests for human input.

This is a developer/advanced-user option. Apple Python 3 (provided by Command Line
Tools) is required for these optional hook scripts. The bundled reader does not
silently add a new executable to your trusted hook commands.

With the app installed in `~/Applications/Codex Dock.app`:

```sh
/usr/bin/python3 "$HOME/Applications/Codex Dock.app/Contents/Resources/install_hooks.py"
```

This prepares `hooks-prets.json` in `~/Library/Application Support/Notifs` without
changing the active hooks file. Read it before choosing to install:

```sh
/usr/bin/python3 "$HOME/Applications/Codex Dock.app/Contents/Resources/install_hooks.py" --install
```

Then explicitly review/approve trust in Codex using `/hooks`. The installer preserves
unrelated hooks and backs up the old hooks file. It does not modify trust records,
approve requests, read prompts or record answers. Moving the app afterward changes
the command path and requires your own reinstallation/review/trust approval.
For a custom Codex home, add `--home '/absolute/path/to/.codex'` to both commands.

Old local Notifs installs may retain trusted commands pointing to their original
bundle and `Data/` redirect. Do not delete those paths until replacing and reapproving
those commands yourself. Public installers do not rewrite them.
