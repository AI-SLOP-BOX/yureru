import '../domain/models.dart';

/// Played items first, most recent first; never-played items retain date order.
int compareRecentlyPlayed(MediaItem a, MediaItem b) {
  final left = a.lastPlayedAt;
  final right = b.lastPlayedAt;
  if (left == null && right != null) return 1;
  if (left != null && right == null) return -1;
  final recent = left != null && right != null ? right.compareTo(left) : 0;
  if (recent != 0) return recent;
  final created = b.createdAt.compareTo(a.createdAt);
  return created != 0 ? created : a.id.compareTo(b.id);
}
