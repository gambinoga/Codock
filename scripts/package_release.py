#!/usr/bin/env python3
"""Allowlist-only release packaging: never copy the workspace/data directory."""
import hashlib
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sysconfig
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    app = ROOT / "Cloches Projets.app"
    if not (app / "Contents/Resources/reader").is_file():
        raise RuntimeError("A release must include the standalone reader. See CONTRIBUTING.md.")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    arch = platform.machine()
    if arch not in ("arm64", "x86_64"): raise RuntimeError("Unsupported release architecture")
    out = ROOT / "dist"; out.mkdir(exist_ok=True)
    archive = out / f"Codex-Dock-macOS-{arch}.zip"
    with tempfile.TemporaryDirectory(prefix="codex-dock-release-") as temporary:
        stage = Path(temporary) / "Codex Dock"; stage.mkdir()
        shutil.copytree(app, stage / "Codex Dock.app", symlinks=True)
        for name in ("README.md", "LICENSE", "THIRD_PARTY.md", "install.sh"):
            shutil.copyfile(ROOT / name, stage / name)
        license_path = Path(sysconfig.get_path("stdlib")) / "LICENSE.txt"
        if not license_path.is_file(): raise RuntimeError("Python license missing; refusing incomplete redistribution")
        shutil.copyfile(license_path, stage / "PYTHON-LICENSE.txt")
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(stage), str(archive)], check=True)
    archive.with_suffix(".zip.sha256").write_text(hashlib.sha256(archive.read_bytes()).hexdigest() + "  " + archive.name + "\n")
    print(archive)


if __name__ == "__main__": main()
