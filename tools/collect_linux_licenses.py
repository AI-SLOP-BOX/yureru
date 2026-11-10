#!/usr/bin/env python3
"""Place app, Flutter, and locked Dart-package license texts in a Linux bundle."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil


ROOT = Path(__file__).resolve().parents[1]
REQUIRED_PACKAGES = {"ffmpeg_kit_flutter_new_full", "media_kit", "media_kit_libs_linux"}


def locked_hosted_packages(lock_text: str) -> dict[str, str]:
    try:
        package_section = lock_text.split("packages:\n", 1)[1]
    except IndexError as error:
        raise SystemExit("pubspec.lock has no packages section") from error

    blocks = re.split(r"(?m)^  ([A-Za-z0-9_.-]+):\n", package_section)
    packages: dict[str, str] = {}
    for index in range(1, len(blocks), 2):
        name, block = blocks[index], blocks[index + 1]
        if re.search(r"(?m)^    source: hosted$", block):
            version = re.search(r'(?m)^    version: "([^\"]+)"$', block)
            if version:
                packages[name] = version.group(1)
    return packages


def copy_license_files(source: Path, target_dir: Path, prefix: str) -> list[Path]:
    copied: list[Path] = []
    for pattern in ("LICENSE*", "LICENCE*", "COPYING*"):
        for license_file in sorted(source.glob(pattern)):
            if not license_file.is_file():
                continue
            destination = target_dir / f"{prefix}-{license_file.name}"
            shutil.copy2(license_file, destination)
            copied.append(destination)
    return copied


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--flutter-root", type=Path, required=True)
    args = parser.parse_args()

    destination = args.bundle / "share/licenses/dev.yureru.yureru"
    destination.mkdir(parents=True, exist_ok=True)
    for existing in destination.iterdir():
        if existing.is_file():
            existing.unlink()

    copied: list[Path] = []
    copied += copy_license_files(ROOT, destination, "yureru")
    copied += copy_license_files(args.flutter_root, destination, "flutter")
    dart_license = args.flutter_root / "bin/cache/dart-sdk/LICENSE"
    if dart_license.is_file():
        shutil.copy2(dart_license, destination / "dart-sdk-LICENSE")
        copied.append(destination / "dart-sdk-LICENSE")
    engine_license = args.flutter_root / "bin/cache/artifacts/engine/linux-x64/LICENSE"
    if engine_license.is_file():
        shutil.copy2(engine_license, destination / "flutter-engine-LICENSE")
        copied.append(destination / "flutter-engine-LICENSE")

    pub_cache = Path(os.environ.get("PUB_CACHE", Path.home() / ".pub-cache"))
    hosted_root = pub_cache / "hosted/pub.dev"
    locked = locked_hosted_packages((ROOT / "pubspec.lock").read_text(encoding="utf-8"))
    missing_required = REQUIRED_PACKAGES - locked.keys()
    if missing_required:
        raise SystemExit(f"Required native packages missing from pubspec.lock: {sorted(missing_required)}")

    missing_licenses: list[str] = []
    for name, version in sorted(locked.items()):
        package_dir = hosted_root / f"{name}-{version}"
        files = copy_license_files(package_dir, destination, f"{name}-{version}")
        if name in REQUIRED_PACKAGES and not files:
            missing_licenses.append(name)
    if missing_licenses:
        raise SystemExit(f"Required package license text not found: {sorted(missing_licenses)}")

    index = destination / "THIRD_PARTY_LICENSES.txt"
    index.write_text(
        "Yureru Linux bundle license texts\n"
        "=================================\n\n"
        "This directory contains Yureru, Flutter/Dart, and locked Dart package "
        "license texts. Native libraries supplied by the Flatpak runtime or "
        "Homebrew dependencies retain their own package license information.\n\n"
        + "\n".join(f"- {path.name}" for path in sorted(copied))
        + "\n",
        encoding="utf-8",
    )
    print(f"Collected {len(copied)} license text files into {destination}")


if __name__ == "__main__":
    main()
