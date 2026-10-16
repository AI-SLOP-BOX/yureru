import 'package:flutter/material.dart';

/// yureru modern theme palette
/// Ultra-deep obsidian black canvas, translucent surfaces, and vibrant cyan-violet glow.
const kBg = Color(0xFF030304);
const kPanel = Color(0xCC0A0A0E); // 80% opacity for frosted glass
const kPanelSolid = Color(0xFF0D0D12);
const kPanelAlt = Color(0xFF14141B);
const kCard = Color(0xFF161620);
const kCardHover = Color(0xFF222230);
const kGlassBorder = Color(0x1FFFFFFF); // 12% white highlight
const kGlassHighlight = Color(0x28FFFFFF); // 16% white reflection
const kAccent = Color(0xFF8B5CF6); // Vibrant Electric Purple
const kAccentLight = Color(0xFFA78BFA); // Soft Lavender Glow
const kAccentCyan = Color(0xFF06B6D4); // Neon Cyan for secondary accents
const kTextPrimary = Color(0xFFF8FAFC);
const kTextSub = Color(0xFF94A3B8);
const kTextMuted = Color(0xFF64748B);

ThemeData yureruTheme({bool isDark = true}) {
  return isDark ? yureruDarkTheme() : yureruLightTheme();
}

ThemeData yureruDarkTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: kAccent,
  );
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    dividerColor: kGlassBorder,
    textTheme: base.textTheme.apply(
      bodyColor: kTextPrimary,
      displayColor: kTextPrimary,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: kAccentLight,
      thumbColor: Colors.white,
      inactiveTrackColor: Colors.white12,
      overlayColor: kAccent.withValues(alpha: 0.2),
      trackHeight: 3.5,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kPanelAlt,
      hintStyle: const TextStyle(color: kTextMuted, fontSize: 13.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: kGlassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: kGlassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: kAccentLight, width: 1.5),
      ),
      isDense: true,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: kTextSub,
      titleTextStyle: TextStyle(
        color: kTextPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      subtitleTextStyle: TextStyle(color: kTextSub, fontSize: 12),
    ),
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(Colors.white70),
        overlayColor: WidgetStatePropertyAll(Color(0x1AFFFFFF)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: kGlassBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kGlassBorder),
      ),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
    ),
    scrollbarTheme: base.scrollbarTheme.copyWith(
      thickness: const WidgetStatePropertyAll(5.0),
      radius: const Radius.circular(999),
      thumbColor: const WidgetStatePropertyAll(Colors.white24),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: kAccentLight,
      selectionColor: kAccent.withValues(alpha: 0.35),
      selectionHandleColor: kAccentLight,
    ),
  );
}

ThemeData yureruLightTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: kAccent,
  );
  return base.copyWith(
    // Soft off-white canvas — far more premium than pure white
    scaffoldBackgroundColor: const Color(0xFFF1F3F9),
    dividerColor: const Color(0x18000000),
    textTheme: base.textTheme.apply(
      // Deep indigo-slate — pairs beautifully with lavender accent
      bodyColor: const Color(0xFF1E1B4B),
      displayColor: const Color(0xFF1E1B4B),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: kAccent,
      thumbColor: kAccent,
      inactiveTrackColor: const Color(0x22000000),
      overlayColor: kAccent.withValues(alpha: 0.15),
      trackHeight: 3.5,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFEEF0F7),
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: Color(0x1A000000)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: Color(0x1A000000)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: kAccent, width: 1.5),
      ),
      isDense: true,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Color(0xFF333333),
      selectedColor: Colors.black,
      selectedTileColor: Color(0x0F000000),
      titleTextStyle: TextStyle(
        color: Color(0xFF1E1B4B),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      subtitleTextStyle: TextStyle(color: Color(0xFF64748B), fontSize: 12),
    ),
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(Color(0xFF222222)),
        overlayColor: WidgetStatePropertyAll(Color(0x0A6D28D9)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kAccent,
        side: const BorderSide(color: Color(0xFFD1D5DB)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0x18000000)),
      ),
      contentTextStyle: const TextStyle(color: Color(0xFF1E1B4B), fontSize: 13),
    ),
    scrollbarTheme: base.scrollbarTheme.copyWith(
      thickness: const WidgetStatePropertyAll(5.0),
      radius: const Radius.circular(999),
      thumbColor: const WidgetStatePropertyAll(Color(0x448B5CF6)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: kAccent,
      selectionColor: kAccent.withValues(alpha: 0.20),
      selectionHandleColor: kAccent,
    ),
  );
}

// ---- Theme-adaptive surface color helpers ----
// These let widgets automatically use the correct surface color
// for dark (obsidian) and light (frosted pearl) modes.

/// Sidebar / top-bar panel background (translucent in dark, frosted in light).
Color themePanel(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? kPanel : const Color(0xF0FAFAFF);
}

/// Solid background for bottom bars and secondary panels.
Color themePanelSolid(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? kPanelSolid : const Color(0xFFF8F9FE);
}

/// Card / item background.
Color themeCard(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? kCard : const Color(0xFFFFFFFF);
}

/// Subtle border / glass separator.
Color themeBorder(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? kGlassBorder : const Color(0x1A000000);
}

/// Primary text color (already theme-aware via Theme.of).
Color themeTextPrimary(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? kTextPrimary : const Color(0xFF1E1B4B);
}

/// Secondary / subtitle text.
Color themeTextSub(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? kTextSub : const Color(0xFF64748B);
}

/// Deterministic per-id gradient so every thumbnail looks distinct.
LinearGradient thumbGradient(String seed) {
  final hue =
      seed.runes.fold<int>(17, (a, r) => (a * 31 + r) & 0x7fffffff) % 360;
  final c1 = HSVColor.fromAHSV(1, hue.toDouble(), 0.6, 0.78).toColor();
  final c2 = HSVColor.fromAHSV(1, (hue + 45) % 360, 0.65, 0.42).toColor();
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
        child: Icon(
          Icons.music_video_rounded,
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
