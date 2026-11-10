/// Splits a creator credit into individual names when common collaboration
/// separators are used. A plain credit remains a single name.
List<String> splitCreatorNames(String? credit) {
  if (credit == null || credit.trim().isEmpty) return const [];
  return credit
      .split(
        RegExp(
          // A slash is valid in creator names (for example, band/project
          // names), so only split on explicit collaboration separators.
          r'\s*(?:,|，|、|・|&|＆|×|\+|\bfeat\.?|\bft\.?|\bwith\b|\band\b)\s*',
          caseSensitive: false,
        ),
      )
      .map((name) => name.trim())
      // Media tags commonly use a dash as a placeholder for an absent credit.
      // Treat it as missing so player metadata never presents it as a name.
      .where(
        (name) => name.isNotEmpty && !RegExp(r'^[\-‐‑‒–—―]+$').hasMatch(name),
      )
      .toList();
}

/// Presents co-creator credits with a compact middle-dot separator.
String formatCreatorNames(String? credit) =>
    splitCreatorNames(credit).join('・');
