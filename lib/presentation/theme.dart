import 'package:flutter/material.dart';
import 'widgets/app_svg_icon.dart';

// Calm charcoal surfaces let artwork carry its own color; a warm coral accent
// gives selected and active playback controls a clear, non-purple identity.
const kBg = Color(0xFF181818);
const kPanel = Color(0xE6202020);
const kPanelSolid = Color(0xFF222222);
const kPanelAlt = Color(0xFF2A2A2A);
const kCard = Color(0xFF303030);
const kCardHover = Color(0xFF3B3B3B);
const kGlassBorder = Color(0xFF484848);
const kGlassHighlight = Color(0xFF565656);
const kAccent = Color(0xFF9B533F);
const kAccentLight = Color(0xFFE4A087);
const kTextPrimary = Color(0xFFEBEBEB);
const kTextSub = Color(0xFFBDBDBD);
const kTextMuted = Color(0xFFA1A1A1);
const kLightBg = Color(0xFFF5F5F5);
const kLightPanel = Color(0xFFEDEDED);
const kLightCard = Color(0xFFFFFFFF);
const kLightBorder = Color(0xFFDADADA);
const kLightText = Color(0xFF242424);
const kLightSub = Color(0xFF626262);

ThemeData yureruTheme({bool isDark = true}) => _theme(isDark);
ThemeData yureruDarkTheme({
  Color? accentColor,
  Color? backgroundColor,
  Color? surfaceColor,
  Color? textColor,
  double cornerRadius = 16,
  double fontScale = 1,
}) => _theme(
  true,
  accentColor: accentColor,
  backgroundColor: backgroundColor,
  surfaceColor: surfaceColor,
  textColor: textColor,
  cornerRadius: cornerRadius,
  fontScale: fontScale,
);
ThemeData yureruLightTheme({
  Color? accentColor,
  Color? backgroundColor,
  Color? surfaceColor,
  Color? textColor,
  double cornerRadius = 16,
  double fontScale = 1,
}) => _theme(
  false,
  accentColor: accentColor,
  backgroundColor: backgroundColor,
  surfaceColor: surfaceColor,
  textColor: textColor,
  cornerRadius: cornerRadius,
  fontScale: fontScale,
);

ThemeData _theme(
  bool dark, {
  Color? accentColor,
  Color? backgroundColor,
  Color? surfaceColor,
  Color? textColor,
  double cornerRadius = 16,
  double fontScale = 1,
}) {
  final bg = backgroundColor ?? (dark ? kBg : kLightBg);
  final accent = accentColor ?? kAccent;
  final accentHighlight = accent == kAccent
      ? kAccentLight
      : Color.lerp(accent, Colors.white, dark ? 0.34 : 0)!;
  final panel =
      surfaceColor ??
      (dark ? Color.lerp(bg, Colors.white, 0.045)! : kLightPanel);
  final panelAlt = dark ? Color.lerp(bg, Colors.white, 0.074)! : kLightPanel;
  final card = dark ? Color.lerp(bg, Colors.white, 0.104)! : kLightCard;
  final cardHover = dark
      ? Color.lerp(bg, Colors.white, 0.152)!
      : const Color(0xFFE6E6E6);
  final accentContainer = Color.lerp(
    dark ? bg : Colors.white,
    accent,
    dark ? 0.32 : 0.13,
  )!;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: accent,
        dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
        brightness: dark ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: dark ? accentHighlight : accent,
        onPrimary: dark ? const Color(0xFF242424) : Colors.white,
        primaryContainer: accentContainer,
        onPrimaryContainer: accentContainer.computeLuminance() > 0.45
            ? const Color(0xFF242424)
            : Colors.white,
        secondary: dark ? kTextSub : kLightSub,
        surface: dark ? panel : kLightCard,
        surfaceContainerLowest: bg,
        surfaceContainerLow: panel,
        surfaceContainer: panelAlt,
        surfaceContainerHigh: card,
        surfaceContainerHighest: cardHover,
        onSurface: textColor ?? (dark ? kTextPrimary : kLightText),
        onSurfaceVariant: dark ? kTextSub : kLightSub,
        outline: dark ? const Color(0xFF787878) : const Color(0xFF858585),
        outlineVariant: dark ? kGlassBorder : kLightBorder,
        surfaceTint: Colors.transparent,
      );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final radius = cornerRadius.clamp(0, 48).toDouble();
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
  );
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    extensions: [
      YureruColors(
        accent: accent,
        accentHighlight: accentHighlight,
        background: bg,
        panel: panel,
        card: card,
      ),
    ],
    dividerColor: scheme.outlineVariant,
    textTheme: base.textTheme
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
        .apply(fontSizeFactor: fontScale.clamp(0.75, 1.5).toDouble()),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: rounded,
      textStyle: TextStyle(color: scheme.onSurface),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: panel,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: TextStyle(color: scheme.onSurface, fontSize: 13),
      secondaryLabelStyle: TextStyle(
        color: scheme.onPrimaryContainer,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(rounded),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primaryContainer
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: 0.38)
              : states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: scheme.primary,
      thumbColor: scheme.primary,
      inactiveTrackColor: scheme.outlineVariant,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
      trackHeight: 3.5,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panelAlt,
      hintStyle: TextStyle(
        color: dark ? kTextMuted : kLightSub,
        fontSize: 13.5,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      isDense: true,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      selectedColor: scheme.onPrimaryContainer,
      selectedTileColor: scheme.primaryContainer,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      subtitleTextStyle: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 12,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => scheme.onSurfaceVariant.withValues(
            alpha: states.contains(WidgetState.disabled) ? 0.38 : 1,
          ),
        ),
        overlayColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: 0.08),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: dark
            ? const Color(0xFFE7E7E7)
            : const Color(0xFF282828),
        foregroundColor: dark ? const Color(0xFF181818) : Colors.white,
        elevation: 0,
        shape: rounded,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outlineVariant),
        shape: rounded,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        shape: rounded,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: rounded.copyWith(side: BorderSide(color: scheme.outlineVariant)),
      contentTextStyle: TextStyle(color: scheme.onSurface, fontSize: 13),
    ),
    scrollbarTheme: base.scrollbarTheme.copyWith(
      thickness: const WidgetStatePropertyAll(5),
      radius: const Radius.circular(999),
      thumbColor: WidgetStatePropertyAll(
        scheme.onSurfaceVariant.withValues(alpha: 0.38),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.22),
      selectionHandleColor: scheme.primary,
    ),
  );
}

Color themePanel(BuildContext context) =>
    Theme.of(context).extension<YureruColors>()?.panel ??
    (Theme.of(context).brightness == Brightness.dark ? kPanel : kLightBg);
Color themePanelSolid(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerLow;
Color themeCard(BuildContext context) =>
    Theme.of(context).extension<YureruColors>()?.card ??
    (Theme.of(context).brightness == Brightness.dark ? kCard : kLightCard);
Color themeCardHover(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerHighest;
Color themeBorder(BuildContext context) =>
    Theme.of(context).colorScheme.outlineVariant;
Color themeTextPrimary(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface;
Color themeTextSub(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;
Color playerTransportColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFA9A9A9)
    : const Color(0xFF5D5D5D);

class YureruColors extends ThemeExtension<YureruColors> {
  const YureruColors({
    required this.accent,
    required this.accentHighlight,
    required this.background,
    required this.panel,
    required this.card,
  });

  final Color accent;
  final Color accentHighlight;
  final Color background;
  final Color panel;
  final Color card;

  @override
  YureruColors copyWith({
    Color? accent,
    Color? accentHighlight,
    Color? background,
    Color? panel,
    Color? card,
  }) => YureruColors(
    accent: accent ?? this.accent,
    accentHighlight: accentHighlight ?? this.accentHighlight,
    background: background ?? this.background,
    panel: panel ?? this.panel,
    card: card ?? this.card,
  );

  @override
  YureruColors lerp(ThemeExtension<YureruColors>? other, double t) {
    if (other is! YureruColors) return this;
    return YureruColors(
      accent: Color.lerp(accent, other.accent, t)!,
      accentHighlight: Color.lerp(accentHighlight, other.accentHighlight, t)!,
      background: Color.lerp(background, other.background, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      card: Color.lerp(card, other.card, t)!,
    );
  }
}

Color themeAccent(BuildContext context) =>
    Theme.of(context).extension<YureruColors>()?.accent ?? kAccent;
Color themeAccentHighlight(BuildContext context) =>
    Theme.of(context).extension<YureruColors>()?.accentHighlight ??
    kAccentLight;

/// Deterministic music-cover gradient for items without usable artwork.
LinearGradient thumbGradient(String seed) {
  const hues = [8.0, 27.0, 43.0, 128.0, 167.0, 190.0, 336.0];
  final hash = seed.runes.fold<int>(17, (a, r) => (a * 31 + r) & 0x7fffffff);
  final hue = hues[hash % hues.length];
  final c1 = HSVColor.fromAHSV(1, hue, 0.62, 0.82).toColor();
  final c2 = HSVColor.fromAHSV(1, (hue + 16) % 360, 0.72, 0.5).toColor();
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [c1, c2],
  );
}

String fmtDuration(Duration d) {
  if (d <= Duration.zero) return '0:00';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}

/// Display title after removing invisible characters from file metadata.
/// Empty or whitespace-only names remain empty.
String displayTitle(String s) {
  final t = s.replaceAll(RegExp('[\u200b\ufeff\u200c\u200d\u2060]'), '').trim();
  return t;
}

/// Gradient thumbnail placeholder (no real frames extracted yet).
class ThumbBox extends StatelessWidget {
  final String seed;
  final double size;
  final double radius;
  final bool expand;
  const ThumbBox({
    super.key,
    required this.seed,
    this.size = 44,
    this.radius = 8,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: expand ? null : size,
      height: expand ? null : size,
      decoration: BoxDecoration(
        gradient: thumbGradient(seed),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: AppSvgIcon(
          'music_note',
          color: Colors.white.withValues(alpha: 0.8),
          size: expand ? 36 : size * 0.45,
        ),
      ),
    );
    if (expand) {
      return SizedBox.expand(child: box);
    }
    return box;
  }
}
