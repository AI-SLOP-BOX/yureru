import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../domain/creator_names.dart';
import '../../domain/models.dart';
import '../theme.dart';
import 'duration_text.dart';
import 'thumb_image.dart';

/// Global search palette (Cmd/Ctrl+K or the search icon): unified results
/// across videos and playlists. Supports keyboard navigation (Up/Down/Enter),
/// artist search, and instant clear.
class SearchOverlay extends ConsumerStatefulWidget {
  final ValueChanged<String> onOpenPlaylist;
  const SearchOverlay({super.key, required this.onOpenPlaylist});

  @override
  ConsumerState<SearchOverlay> createState() => _SearchOverlayState();

  static Future<void> show(
    BuildContext context,
    ValueChanged<String> onOpenPlaylist,
  ) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (dlgContext) {
        final isDark = Theme.of(dlgContext).brightness == Brightness.dark;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 80,
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xF214141E)
                    : Colors.white.withValues(alpha: 0.98),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.2),
                    blurRadius: 32,
                    spreadRadius: 4,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: SearchOverlay(onOpenPlaylist: onOpenPlaylist),
            ),
          ),
        );
      },
    );
  }
}

class _SearchOverlayState extends ConsumerState<SearchOverlay> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  String _q = '';
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = _handleKeyEvent;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _clear() {
    _ctrl.clear();
    setState(() {
      _q = '';
      _selectedIndex = 0;
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final lib = ref.read(libraryProvider);
    final q = _q.trim().toLowerCase();
    final videos = lib.media.where((m) {
      if (q.isEmpty) return true;
      final titleMatch = m.title.toLowerCase().contains(q);
      final artistMatch = m.artist?.toLowerCase().contains(q) ?? false;
      return titleMatch || artistMatch;
    }).toList();

    final playlists = lib.playlists.where((p) {
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q);
    }).toList();

    final totalCount = playlists.length + videos.length;
    if (totalCount == 0) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % totalCount;
      });
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1 + totalCount) % totalCount;
      });
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      _activateIndex(_selectedIndex, playlists, videos, lib);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _activateIndex(
    int index,
    List<Playlist> playlists,
    List<MediaItem> videos,
    LibraryState lib,
  ) {
    if (index < playlists.length) {
      final pl = playlists[index];
      Navigator.pop(context);
      widget.onOpenPlaylist(pl.id);
    } else {
      final vIdx = index - playlists.length;
      if (vIdx < videos.length) {
        final targetVideo = videos[vIdx];
        Navigator.pop(context);
        ref.read(videoOpenRequestProvider.notifier).state = targetVideo.id;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final q = _q.trim().toLowerCase();

    // Support both title and artist search
    final videos = lib.media.where((m) {
      if (q.isEmpty) return true;
      final titleMatch = m.title.toLowerCase().contains(q);
      final artistMatch = m.artist?.toLowerCase().contains(q) ?? false;
      return titleMatch || artistMatch;
    }).toList();

    final playlists = lib.playlists.where((p) {
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q);
    }).toList();

    final totalCount = playlists.length + videos.length;
    if (_selectedIndex >= totalCount && totalCount > 0) {
      _selectedIndex = 0;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
          child: TextField(
            controller: _ctrl,
            focusNode: _focusNode,
            autofocus: true,
            onChanged: (v) => setState(() {
              _q = v;
              _selectedIndex = 0;
            }),
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: '曲名、アーティスト、プレイリストを検索...',
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 20,
                color: kTextSub,
              ),
              suffixIcon: _ctrl.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'クリア',
                      splashRadius: 16,
                      icon: const Icon(
                        Icons.clear_rounded,
                        size: 18,
                        color: kTextSub,
                      ),
                      onPressed: _clear,
                    )
                  : null,
            ),
            onSubmitted: (_) {
              _activateIndex(_selectedIndex, playlists, videos, lib);
            },
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            children: [
              if (playlists.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 6, 12, 4),
                  child: Text(
                    'プレイリスト',
                    style: TextStyle(
                      fontSize: 12,
                      color: kTextSub,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (int i = 0; i < playlists.length && i < 5; i++) ...[
                  () {
                    final pl = playlists[i];
                    final isSelected = _selectedIndex == i;
                    return Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? kAccent.withValues(alpha: 0.18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: isSelected
                            ? Border.all(
                                color: kAccentLight.withValues(alpha: 0.5),
                                width: 1,
                              )
                            : null,
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        leading: ThumbImage(
                          seed: pl.id,
                          mediaId: pl.mediaIds.isEmpty
                              ? null
                              : lib.byId(pl.mediaIds.first)?.id,
                          localPath: pl.mediaIds.isEmpty
                              ? null
                              : lib.byId(pl.mediaIds.first)?.localPath,
                          size: 40,
                        ),
                        title: Text(
                          displayTitle(pl.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${pl.mediaIds.length}本の動画',
                          style: const TextStyle(fontSize: 12, color: kTextSub),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.keyboard_return_rounded,
                                size: 16,
                                color: kAccentLight,
                              )
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onOpenPlaylist(pl.id);
                        },
                      ),
                    );
                  }(),
                ],
              ],
              if (videos.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Text(
                    '動画・楽曲',
                    style: TextStyle(
                      fontSize: 12,
                      color: kTextSub,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (int i = 0; i < videos.length && i < 8; i++) ...[
                  () {
                    final m = videos[i];
                    final globalIdx = playlists.length + i;
                    final isSelected = _selectedIndex == globalIdx;
                    final subtitleText =
                        m.artist != null && m.artist!.isNotEmpty
                        ? formatCreatorNames(m.artist)
                        : null;

                    return Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? kAccent.withValues(alpha: 0.18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: isSelected
                            ? Border.all(
                                color: kAccentLight.withValues(alpha: 0.5),
                                width: 1,
                              )
                            : null,
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        leading: ThumbImage(
                          seed: m.id,
                          mediaId: m.id,
                          localPath: m.localPath,
                          size: 40,
                          radius: 8,
                        ),
                        title: Text(
                          displayTitle(m.title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: subtitleText != null
                            ? Text(
                                subtitleText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: kTextSub,
                                ),
                              )
                            : DurationText(
                                mediaId: m.id,
                                localPath: m.localPath,
                                durationMs: m.durationMs,
                              ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (subtitleText != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: DurationText(
                                  mediaId: m.id,
                                  localPath: m.localPath,
                                  durationMs: m.durationMs,
                                ),
                              ),
                            if (isSelected)
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                                color: kAccentLight,
                              ),
                          ],
                        ),
                        onTap: () =>
                            _activateIndex(globalIdx, playlists, videos, lib),
                      ),
                    );
                  }(),
                ],
              ],
              if (videos.isEmpty && playlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                    child: Text(
                      '見つかりませんでした',
                      style: TextStyle(color: kTextSub, fontSize: 13),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
