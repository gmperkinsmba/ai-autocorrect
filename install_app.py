#!/usr/bin/env python3
"""Install only an AI Autocorrect bundle built by build_app.py."""
from __future__ import annotations

import datetime
import plistlib
import shutil
import sys
from pathlib import Path

APP_NAME = "AI Autocorrect"
PRODUCT_ID = "io.github.gmperkinsmba.ai-autocorrect"
OWNER_MARKER = "ai-autocorrect-native-local-build-owner-v1"
ROOT = Path(__file__).resolve().parent


def owned(app: Path) -> bool:
    if app.is_symlink():
        return False
    plist = app / "Contents" / "Info.plist"
    marker = app / "Contents" / "Resources" / "desktop-app-owner.txt"
    if not plist.is_file() or not marker.is_file():
        return False
    try:
        info = plistlib.loads(plist.read_bytes())
        lines = marker.read_text(encoding="utf-8").splitlines()
        return info.get("CFBundleIdentifier") == PRODUCT_ID and OWNER_MARKER in lines
    except (OSError, ValueError, plistlib.InvalidFileException):
        return False


def main() -> int:
    if sys.platform != "darwin":
        raise SystemExit("AI Autocorrect is packaged for macOS only.")
    source = ROOT / "dist" / f"{APP_NAME}.app"
    if not owned(source):
        raise SystemExit("The dist app is missing its expected bundle ID or owner marker.")
    destination_dir = Path.home() / "Applications"
    destination_dir.mkdir(parents=True, exist_ok=True)
    destination = destination_dir / f"{APP_NAME}.app"
    if destination.exists():
        if destination.is_symlink():
            raise SystemExit(f"Refusing to replace a symlink: {destination}")
        if not owned(destination):
            raise SystemExit(f"Refusing to replace an unrelated app: {destination}")
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = destination_dir / f"{APP_NAME}.app.previous-{stamp}"
        if backup.exists():
            raise SystemExit("The owned backup path already exists; refusing to overwrite it.")
        destination.rename(backup)
        print(f"Retained owned backup: {backup}")
    shutil.copytree(source, destination, symlinks=False)
    print(f"Installed {destination}")
    print("Open AI Autocorrect from Finder or add it to the Dock.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
