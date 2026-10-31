#!/usr/bin/env python3
"""Build the native macOS AI Autocorrect app bundle."""
from __future__ import annotations

import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
APP_NAME = "AI Autocorrect"
PRODUCT_ID = "io.github.gmperkinsmba.ai-autocorrect"
OWNER_MARKER = "ai-autocorrect-native-local-build-owner-v1"


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(args, cwd=ROOT, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else ""


def main() -> int:
    if sys.platform != "darwin":
        raise SystemExit("AI Autocorrect is packaged for macOS only.")
    run("swift", "build", "--configuration", "release", "--product", APP_NAME)
    bin_path = Path(run("swift", "build", "--show-bin-path", capture=True))
    executable = bin_path / APP_NAME
    if not executable.is_file():
        raise SystemExit(f"Swift did not produce the expected app executable: {executable.name}")

    app = ROOT / "dist" / f"{APP_NAME}.app"
    if app.is_symlink():
        raise SystemExit("Refusing to replace a symlink at the dist app path.")
    if app.exists():
        info_path = app / "Contents" / "Info.plist"
        marker_path = app / "Contents" / "Resources" / "desktop-app-owner.txt"
        if not info_path.exists() or not marker_path.exists():
            raise SystemExit("Refusing to replace an unmarked app bundle in dist.")
        old_info = plistlib.loads(info_path.read_bytes())
        if old_info.get("CFBundleIdentifier") != PRODUCT_ID or OWNER_MARKER not in marker_path.read_text().splitlines():
            raise SystemExit("Refusing to replace a bundle with a different owner or identifier.")
        shutil.rmtree(app)
    contents = app / "Contents"
    macos = contents / "MacOS"
    resources = contents / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)
    shutil.copy2(executable, macos / APP_NAME)
    (resources / "desktop-app-owner.txt").write_text(f"{APP_NAME} native bundle\n{PRODUCT_ID}\n{OWNER_MARKER}\n", encoding="utf-8")
    info = {
        "CFBundleName": APP_NAME,
        "CFBundleDisplayName": APP_NAME,
        "CFBundleExecutable": APP_NAME,
        "CFBundleIdentifier": PRODUCT_ID,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "14.0",
        "LSUIElement": True,
        "NSHighResolutionCapable": True,
    }
    with (contents / "Info.plist").open("wb") as file:
        plistlib.dump(info, file, sort_keys=True)
    run("codesign", "--force", "--deep", "--sign", "-", "--timestamp=none", str(app))
    print(f"Built {app}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
