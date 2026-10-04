import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../nav.dart';
import '../theme.dart';
import 'thumb_image.dart';
import 'yureru_logo.dart';

/// Left sidebar: logo, navigation, and playlist list with a small "+" button
/// (playlist creation only — media import lives exclusively in Settings).
class Sidebar extends ConsumerWidget {
  final double width;
  final Nav nav;
  final String? detailPlaylistId;
  final bool viewingPlayer;
  final ValueChanged<Nav> onNav;
  final ValueChanged<String> onPlaylist;
  final VoidCallback? onLogoHome;
  const Sidebar({
    super.key,
    this.width = 248,
    required this.nav,
    required this.detailPlaylistId,
    this.viewingPlayer = false,
    required this.onNav,
    required this.onPlaylist,
    this.onLogoHome,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final playlists = lib.playlists;
    if (collapsed) return _rail(context, ref);
    return Container(
      width: width,
      color: themePanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onLogoHome,
              child: const YureruBrandHeader(iconSize: 32),
            ),
          ),
          const SizedBox(height: 24),
          _NavItem(
            icon: Icons.home_rounded,
            label: 'ライブラリ',
            selected:
                nav == Nav.library &&
                detailPlaylistId == null &&
                !viewingPlayer,
            onTap: () => onNav(Nav.library),
          ),
          _NavItem(
            icon: Icons.playlist_play_rounded,
            label: 'プレイリスト',
            selected:
                nav == Nav.playlists &&
                detailPlaylistId == null &&
                !viewingPlayer,
            onTap: () => onNav(Nav.playlists),
          ),
          _NavItem(
            icon: Icons.video_library_rounded,
            label: 'すべての動画',
            selected: nav == Nav.videos && !viewingPlayer,
            onTap: () => onNav(Nav.videos),
          ),
          _NavItem(
            icon: Icons.settings_rounded,
            label: '設定',
            selected: nav == Nav.settings && !viewingPlayer,
            onTap: () => onNav(Nav.settings),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider(height: 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'プレイリスト',
                    style: TextStyle(
                      color: kTextSub,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: '新規プレイリスト',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _newPlaylist(context, ref),
                ),
              ],
            ),
          ),
          Expanded(
            child: playlists.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '＋から新規作成できます',
                      style: TextStyle(color: kTextSub, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    itemCount: playlists.length,
                    itemBuilder: (c, i) {
                      final pl = playlists[i];
                      final first = pl.mediaIds.isEmpty
                          ? null
                          : lib.byId(pl.mediaIds.first);
                      return _PlaylistItem(
                        title: pl.name,
                        count: pl.mediaIds.length,
                        seed: pl.id,
                        thumbMediaId: first?.id,
                        thumbPath: first?.localPath,
                        selected: detailPlaylistId == pl.id && !viewingPlayer,
                        onTap: () => onPlaylist(pl.id),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Collapsed icon rail (labels + playlist list hidden).
  Widget _rail(BuildContext context, WidgetRef ref) {
    bool sel(bool v) => v && !viewingPlayer;
    return Container(
      width: 76,
      color: themePanel(context),
      child: Column(
        children: [
          const SizedBox(height: 16),
          _LogoButton(onTap: onLogoHome),
          const SizedBox(height: 20),
          _RailButton(
            icon: Icons.home_rounded,
            tooltip: 'ライブラリ',
            selected: sel(nav == Nav.library && detailPlaylistId == null),
            onTap: () => onNav(Nav.library),
          ),
          _RailButton(
            icon: Icons.playlist_play_rounded,
            tooltip: 'プレイリスト',
            selected: sel(nav == Nav.playlists && detailPlaylistId == null),
            onTap: () => onNav(Nav.playlists),
          ),
          _RailButton(
            icon: Icons.video_library_rounded,
            tooltip: 'すべての動画',
            selected: sel(nav == Nav.videos),
            onTap: () => onNav(Nav.videos),
          ),
          _RailButton(
            icon: Icons.settings_rounded,
            tooltip: '設定',
            selected: sel(nav == Nav.settings),
            onTap: () => onNav(Nav.settings),
          ),
          const SizedBox(height: 8),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: '新規プレイリスト',
            visualDensity: VisualDensity.compact,
            onPressed: () => _newPlaylist(ref.context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _newPlaylist(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新規プレイリスト'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'プレイリスト名'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('作成'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(libraryProvider.notifier).createPlaylist(name.trim());
    }
  }
}

class _LogoButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _LogoButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    final logo = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Image.asset(
        'assets/yureru_logo.png',
        width: 40,
        height: 40,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.graphic_eq, color: Colors.white, size: 26),
        ),
      ),
    );
    if (onTap == null) return logo;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Tooltip(message: 'ライブラリに戻る', child: logo),
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? kAccent.withValues(alpha: 0.22) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Tooltip(
            message: tooltip,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Icon(
                icon,
                size: 22,
                color: selected ? kAccentLight : kTextSub,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected
              ? (isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            hoverColor: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Active Pill Indicator Bar
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 3.5,
                    height: selected ? 18 : 0,
                    decoration: BoxDecoration(
                      color: kAccent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(width: selected ? 10 : 13.5),
                  Icon(
                    icon,
                    size: 22,
                    color: selected
                        ? (isDark ? Colors.white : Colors.black)
                        : (isDark ? kTextSub : Colors.black54),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected
                            ? (isDark ? Colors.white : Colors.black)
                            : (isDark ? kTextSub : Colors.black87),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistItem extends StatelessWidget {
  final String title;
  final int count;
  final String seed;
  final String? thumbMediaId;
  final String? thumbPath;
  final bool selected;
  final VoidCallback onTap;
  const _PlaylistItem({
    required this.title,
    required this.count,
    required this.seed,
    this.thumbMediaId,
    this.thumbPath,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected
              ? (isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.06))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            hoverColor: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ThumbImage(
                      seed: seed,
                      mediaId: thumbMediaId,
                      localPath: thumbPath,
                      size: 38,
                      radius: 6,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle(title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected
                                ? (isDark ? Colors.white : Colors.black)
                                : (isDark ? kTextPrimary : Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '$count本の動画',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? kTextMuted : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
