#!/usr/bin/env python3
"""Render a version-pinned Homebrew formula for a tagged GitHub release."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "Formula" / "yureru.rb"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    if not re.fullmatch(r"\d+\.\d+\.\d+(?:\.\d+)?", args.version):
        raise SystemExit("Version must be a numeric release version (without the v prefix).")
    digest = hashlib.sha256(args.archive.read_bytes()).hexdigest()
    formula = TEMPLATE.read_text(encoding="utf-8")
    formula = re.sub(
        r'url "https://github\.com/AI-SLOP-BOX/yureru/releases/download/v[^/]+/yureru-linux-x64\.tar\.gz"',
        f'url "https://github.com/AI-SLOP-BOX/yureru/releases/download/v{args.version}/yureru-linux-x64.tar.gz"',
        formula,
        count=1,
    )
    formula = re.sub(r'version "[^"]+"', f'version "{args.version}"', formula, count=1)
    formula = re.sub(r'sha256 "[0-9a-f]{64}"', f'sha256 "{digest}"', formula, count=1)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(formula, encoding="utf-8")


if __name__ == "__main__":
    main()
