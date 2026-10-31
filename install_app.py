#!/usr/bin/env python3
"""Install only an AI Autocorrect bundle built by build_app.py."""
from __future__ import annotations

import plistlib
import sys
from pathlib import Path

from install_security import InstallSecurityError, install_signed_bundle

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
    destination = Path.home() / "Applications" / f"{APP_NAME}.app"
    try:
        backup = install_signed_bundle(source, destination, owner_check=owned)
    except (InstallSecurityError, OSError) as exc:
        raise SystemExit(f"Install failed: {exc}") from exc
    if backup is not None:
        print(f"Retained owned backup: {backup}")
    print(f"Installed {destination}")
    print("Open AI Autocorrect from Finder or add it to the Dock.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
