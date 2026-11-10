# Translation workflow

Translation strings live in `lib/presentation/translations/`, grouped by locale.
Each locale file contains maps grouped by use (base, feature, screen, extra, and
library); `shortcuts.dart` holds shortcut maps for every locale. These maps are
assembled in `lib/presentation/i18n.dart`.

## Where to add strings

- `*Base` maps in each locale file: shared playback, navigation, and settings labels.
- `*Feature`, `*Screen`, `*Extra`, and `*Library` maps: strings grouped by feature or screen.
- `shortcuts.dart`: desktop menu and keyboard-shortcut labels for every language.

Keep the key identical across locales. Preserve interpolation placeholders such as
`{count}`, `{title}`, and `{error}` exactly; changing one can break runtime formatting.
Use concise, natural wording for each language instead of translating word by word.

## Check coverage

Run `python3 tools/check_translations.py` to list missing keys and placeholder
mismatches. Add `--strict` in CI or before release to make missing translations
fail the check. Missing strings currently fall back to English, then Japanese, so
an incomplete locale remains usable without unexpectedly switching to Japanese.
