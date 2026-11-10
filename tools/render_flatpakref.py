#!/usr/bin/env python3
"""Create a Flatpak ref once a signed Yureru OSTree repository is hosted."""

from __future__ import annotations

import argparse
import base64
from pathlib import Path
from urllib.parse import urlparse


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-url", required=True, help="HTTPS URL of the hosted OSTree repository")
    parser.add_argument("--gpg-public-key", required=True, type=Path, help="Binary public key exported by gpg --export")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--branch", default="stable")
    args = parser.parse_args()

    parsed_url = urlparse(args.repo_url)
    if parsed_url.scheme != "https" or not parsed_url.netloc:
        raise SystemExit("The Flatpak repository URL must be an HTTPS URL.")
    key = args.gpg_public_key.read_bytes()
    if not key:
        raise SystemExit("The exported GPG public key is empty.")

    contents = "\n".join(
        [
            "[Flatpak Ref]",
            "Name=dev.yureru.yureru",
            f"Branch={args.branch}",
            "Title=Yureru",
            f"Url={args.repo_url.rstrip('/')}/",
            "RuntimeRepo=https://dl.flathub.org/repo/flathub.flatpakrepo",
            "IsRuntime=false",
            f"GPGKey={base64.b64encode(key).decode('ascii')}",
            "",
        ]
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(contents, encoding="utf-8")


if __name__ == "__main__":
    main()
