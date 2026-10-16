/// Splits a creator credit into individual names when common collaboration
/// separators are used. A plain credit remains a single name.
List<String> splitCreatorNames(String? credit) {
  if (credit == null || credit.trim().isEmpty) return const [];
  return credit
      .split(
        RegExp(
          r'\s*(?:,|，|、|・|/|／|&|＆|×|\+|\bfeat\.?|\bft\.?|\bwith\b|\band\b)\s*',
          caseSensitive: false,
        ),
      )
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList();
}

/// Presents co-creator credits with a compact middle-dot separator.
String formatCreatorNames(String? credit) =>
    splitCreatorNames(credit).join('・');
