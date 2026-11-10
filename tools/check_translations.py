#!/usr/bin/env python3
"""Report missing translation keys and placeholder mismatches."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TRANSLATIONS = ROOT / "lib/presentation/translations"
LOCALES = ("ja", "en", "es", "pt", "fr", "de", "ko", "zh_hans", "zh_hant", "ar")
SHORTCUT_NAMES = {"zh_hans": "zhHans", "zh_hant": "zhHant"}
KEY_PATTERN = re.compile(r"^\s*['\"]([^'\"]+)['\"]\s*:", re.MULTILINE)
PLACEHOLDER_PATTERN = re.compile(r"\{([^{}]+)\}")


def keys(path: Path) -> set[str]:
    return set(KEY_PATTERN.findall(path.read_text(encoding="utf-8")))


def values(path: Path) -> dict[str, str]:
    """Read simple Dart string values for placeholder checks."""
    text = path.read_text(encoding="utf-8")
    result: dict[str, str] = {}
    entry = re.compile(
        r"^\s*['\"]([^'\"]+)['\"]\s*:\s*(['\"])((?:\\.|(?!\2).)*?)\2\s*,?\s*$",
        re.MULTILINE,
    )
    for match in entry.finditer(text):
        result[match.group(1)] = match.group(3)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--strict",
        action="store_true",
        help="return a failing exit code when any locale is incomplete",
    )
    args = parser.parse_args()

    canonical = keys(TRANSLATIONS / "en.dart") | keys(TRANSLATIONS / "shortcuts.dart")
    english_values = values(TRANSLATIONS / "en.dart") | values(
        TRANSLATIONS / "shortcuts.dart"
    )
    incomplete = False

    for locale in LOCALES:
        locale_file = TRANSLATIONS / f"{locale}.dart"
        shortcut_file = TRANSLATIONS / "shortcuts.dart"
        locale_keys = keys(locale_file)
        # Shortcut dictionaries share one source file; each locale has a named map.
        shortcut_locale = SHORTCUT_NAMES.get(locale, locale)
        shortcut_source = shortcut_file.read_text(encoding="utf-8")
        block = re.search(
            rf"^const Map<String, String> {re.escape(shortcut_locale)}Shortcuts\s*=\s*\{{(.*?)^\}};",
            shortcut_source,
            re.MULTILINE | re.DOTALL,
        )
        if block:
            locale_keys |= set(KEY_PATTERN.findall(block.group(1)))

        missing = sorted(canonical - locale_keys)
        incomplete |= bool(missing)
        if missing:
            print(f"{locale}: {len(missing)} missing")
            for key in missing:
                print(f"  {key}")
        else:
            print(f"{locale}: complete")

        locale_values = values(locale_file)
        if block:
            # Reuse the value parser on the map body without writing temporary files.
            locale_values.update(
                {
                    match.group(1): match.group(3)
                    for match in re.finditer(
                        r"^\s*['\"]([^'\"]+)['\"]\s*:\s*(['\"])((?:\\.|(?!\2).)*?)\2\s*,?\s*$",
                        block.group(1),
                        re.MULTILINE,
                    )
                }
            )
        mismatched = sorted(
            key
            for key in canonical & locale_keys
            if key in english_values
            and key in locale_values
            and set(PLACEHOLDER_PATTERN.findall(english_values[key]))
            != set(PLACEHOLDER_PATTERN.findall(locale_values[key]))
        )
        if mismatched:
            incomplete = True
            print(f"{locale}: placeholder mismatch: {', '.join(mismatched)}")

    return int(args.strict and incomplete)


if __name__ == "__main__":
    raise SystemExit(main())
