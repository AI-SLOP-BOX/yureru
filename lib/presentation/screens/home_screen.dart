import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/models.dart';
import '../../playback/playback_controller.dart';
import '../theme.dart';
import '../layout_metrics.dart';
import '../widgets/duration_text.dart';
import '../widgets/thumb_image.dart';
import '../widgets/preview_player.dart';

/// Shared page header (search sits in the top bar; pages show a small title).
class PageHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget? actions;
  const PageHeader({
    super.key,
    required this.title,
    this.trailing,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inset = LayoutMetrics.horizontalInset(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 10, inset, 14),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: isDark ? kTextPrimary : const Color(0xFF1E1B4B),
              letterSpacing: -0.5,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: themeCard(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: themeBorder(context)),
              ),
              child: Text(
                trailing!,
                style: TextStyle(
                  fontSize: 12,
                  color: themeTextSub(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          if (actions != null) ...[const Spacer(), actions!],
        ],
      ),
    );
  }
}

/// Library home: playlist grid (player card sits above this in the shell).
class HomeScreen extends ConsumerWidget {
  final ValueChanged<String>? onOpenPlaylist;
  final VoidCallback? onOpenVideos;
  const HomeScreen({super.key, this.onOpenPlaylist, this.onOpenVideos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final query = ref.watch(searchQueryProvider).trim().toLowerCase();
    if (!lib.loaded) return const Center(child: CircularProgressIndicator());
    final playlists = lib.playlists
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
        .toList();
    final matchingSongs = query.isEmpty
        ? <MediaItem>[]
        : lib.media.where((m) {
            final t = m.title.toLowerCase();
            final a = (m.artist ?? '').toLowerCase();
            return t.contains(query) || a.contains(query);
          }).toList();

    if (playlists.isEmpty && lib.media.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.video_library_outlined, size: 56, color: kTextSub),
              SizedBox(height: 14),
              Text(
                'ライブラリは空です',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                '設定 → ライブラリ管理から動画・フォルダをインポートできます',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextSub, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    // The middle scrolls: header + preview are fixed, so CJK line-height
    // variance (the classic 1px Column overflow) can never break this page.
    final headerTrailing = query.isNotEmpty
        ? '${matchingSongs.length}曲 • ${playlists.length}個のプレイリスト'
        : '${playlists.length}個のプレイリスト';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(title: 'ライブラリ', trailing: headerTrailing),
        Expanded(
          child: CustomScrollView(
            slivers: [
              if (query.isEmpty)
                SliverToBoxAdapter(
                  child: _RecentStrip(onOpenVideos: onOpenVideos),
                ),

              // 1. Matching songs/videos section (shown when searching)
              if (query.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.music_note_rounded,
                          size: 18,
                          color: kAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '曲・動画 (${matchingSongs.length}件)',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (matchingSongs.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      child: Text(
                        '一致する曲が見つかりません',
                        style: TextStyle(color: kTextSub, fontSize: 13),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final m = matchingSongs[index];
                        final artistText =
                            m.artist != null && m.artist!.isNotEmpty
                            ? m.artist!
                            : '';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: themeCard(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: themeBorder(context)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 2,
                            ),
                            leading: ThumbImage(
                              seed: m.id,
                              mediaId: m.id,
                              localPath: m.localPath,
                              size: 44,
                              radius: 8,
                            ),
                            title: Text(
                              displayTitle(m.title),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    artistText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: kTextSub,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '• ',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: kTextMuted,
                                  ),
                                ),
                                DurationText(
                                  mediaId: m.id,
                                  localPath: m.localPath,
                                  durationMs: m.durationMs,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: kTextMuted,
                                  ),
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              tooltip: '再生',
                              icon: const Icon(
                                Icons.play_circle_fill_rounded,
                                size: 30,
                                color: kAccent,
                              ),
                              onPressed: () {
                                showPlayerView(ref);
                                final order = [
                                  for (final s in matchingSongs) s.id,
                                ];
                                ref
                                    .read(queueProvider.notifier)
                                    .start(order, shuffle: false);
                                ref.read(queueProvider.notifier).jumpTo(index);
                                ref
                                    .read(playbackControllerProvider)
                                    .openCurrent();
                              },
                            ),
                            onTap: () {
                              showPlayerView(ref);
                              final order = [
                                for (final s in matchingSongs) s.id,
                              ];
                              ref
                                  .read(queueProvider.notifier)
                                  .start(order, shuffle: false);
                              ref.read(queueProvider.notifier).jumpTo(index);
                              ref
                                  .read(playbackControllerProvider)
                                  .openCurrent();
                            },
                          ),
                        );
                      }, childCount: matchingSongs.length),
                    ),
                  ),
              ],

              // 2. Playlists section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                  child: Text(
                    query.isEmpty
                        ? 'あなたのプレイリスト'
                        : 'プレイリスト (${playlists.length}件)',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (playlists.isEmpty)
                SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        query.isEmpty
                            ? 'プレイリストはサイドバーの＋から作成できます'
                            : '一致するプレイリストがありません',
                        style: const TextStyle(color: kTextSub, fontSize: 13),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 230,
                          childAspectRatio: 1.05,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                        ),
                    delegate: SliverChildBuilderDelegate((c, i) {
                      final pl = playlists[i];
                      final first = pl.mediaIds.isEmpty
                          ? null
                          : lib.byId(pl.mediaIds.first);
                      return _PlaylistCard(
                        playlistId: pl.id,
                        name: pl.name,
                        count: pl.mediaIds.length,
                        thumbMediaId: first?.id,
                        thumbPath: first?.localPath,
                        onOpen: onOpenPlaylist == null
                            ? null
                            : () => onOpenPlaylist!(pl.id),
                        onPlay: pl.mediaIds.isEmpty
                            ? null
                            : () {
                                showPlayerView(ref);
                                ref
                                    .read(playbackControllerProvider)
                                    .startPlaylist(pl.id, shuffle: false);
                              },
                        onShuffle: pl.mediaIds.isEmpty
                            ? null
                            : () {
                                showPlayerView(ref);
                                ref
                                    .read(playbackControllerProvider)
                                    .startPlaylist(pl.id, shuffle: true);
                              },
                      );
                    }, childCount: playlists.length),
                  ),
                ),
            ],
          ),
        ),
        const PreviewBar(),
      ],
    );
  }
}

/// Recently-added horizontal strip (newest 10). Plays in library order
/// from the tapped item, like the videos screen.
class _RecentStrip extends ConsumerWidget {
  final VoidCallback? onOpenVideos;
  const _RecentStrip({this.onOpenVideos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    if (!lib.loaded || lib.media.isEmpty) return const SizedBox.shrink();
    final recent = [...lib.media]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final items = recent.take(10).toList();
    final order = [for (final m in lib.media) m.id];
    void play(int recentIndex) {
      final id = items[recentIndex].id;
      showPlayerView(ref);
      ref.read(queueProvider.notifier).start(order, shuffle: false);
      ref.read(queueProvider.notifier).jumpTo(order.indexOf(id));
      ref.read(playbackControllerProvider).openCurrent();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 2, 24, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '最近追加',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              if (items.length > 2)
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onOpenVideos,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '横スクロール',
                            style: TextStyle(
                              fontSize: 11.5,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? kTextMuted
                                  : Colors.black45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? kTextMuted
                                : Colors.black45,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: MediaQuery.sizeOf(context).width < 600 ? 142 : 166,
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0.0, 0.88, 0.94, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(
                horizontal: LayoutMetrics.horizontalInset(context),
              ),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (c, i) {
                final m = items[i];
                return _RecentVideoCard(media: m, onTap: () => play(i));
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _RecentVideoCard extends StatefulWidget {
  final dynamic media;
  final VoidCallback onTap;

  const _RecentVideoCard({required this.media, required this.onTap});

  @override
  State<_RecentVideoCard> createState() => _RecentVideoCardState();
}

class _RecentVideoCardState extends State<_RecentVideoCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.media;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardWidth = LayoutMetrics.recentCardWidth(context);
    final thumbnailWidth = cardWidth - 14;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: cardWidth,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: _hover
                ? (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 200),
                scale: _hover ? 1.03 : 1.0,
                curve: Curves.easeOutCubic,
                child: Container(
                  width: thumbnailWidth,
                  height: thumbnailWidth * 9 / 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: _hover ? 0.5 : 0.25,
                        ),
                        blurRadius: _hover ? 14 : 8,
                        offset: Offset(0, _hover ? 5 : 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ThumbImage(
                        seed: m.id,
                        mediaId: m.id,
                        localPath: m.localPath,
                        radius: 10,
                        expand: true,
                      ),
                      // Hover Play Vignette
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: _hover ? 0.35 : 0.0,
                        child: Container(color: Colors.black),
                      ),
                      // Floating Center Play Button
                      Center(
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 200),
                          scale: _hover ? 1.0 : 0.5,
                          curve: Curves.easeOutBack,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: _hover ? 1.0 : 0.0,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  size: 22,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                displayTitle(m.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? kTextPrimary : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              DurationText(
                mediaId: m.id,
                localPath: m.localPath,
                durationMs: m.durationMs,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? kTextMuted : Colors.black45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatefulWidget {
  final String playlistId;
  final String name;
  final int count;
  final String? thumbMediaId;
  final String? thumbPath;
  final VoidCallback? onOpen;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  const _PlaylistCard({
    required this.playlistId,
    required this.name,
    required this.count,
    this.thumbMediaId,
    this.thumbPath,
    this.onOpen,
    this.onPlay,
    this.onShuffle,
  });

  @override
  State<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<_PlaylistCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _hover
              ? (isDark ? kCardHover : const Color(0xFFE8EAF0))
              : (isDark ? kCard : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hover ? kGlassHighlight : themeBorder(context),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hover ? 0.20 : 0.08),
              blurRadius: _hover ? 16 : 8,
              offset: Offset(0, _hover ? 6 : 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: thumbGradient(widget.playlistId),
                      ),
                      child: widget.thumbPath == null
                          ? const Icon(
                              Icons.playlist_play_rounded,
                              color: Colors.white70,
                              size: 44,
                            )
                          : ThumbImage(
                              seed: widget.playlistId,
                              mediaId: widget.thumbMediaId,
                              localPath: widget.thumbPath,
                              radius: 0,
                              expand: true,
                            ),
                    ),
                    // Dark vignette on hover
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _hover ? 0.35 : 0.0,
                      child: Container(color: Colors.black),
                    ),
                    // Floating Play Button (YT Music signature hover)
                    if (widget.onPlay != null)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutBack,
                          offset: _hover ? Offset.zero : const Offset(0, 0.4),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: _hover ? 1.0 : 0.0,
                            child: Material(
                              color: Colors.white,
                              shape: const CircleBorder(),
                              elevation: 8,
                              shadowColor: Colors.black54,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: widget.onPlay,
                                child: const SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.black,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle(widget.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: themeTextPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.count}本の動画',
                      style: TextStyle(
                        fontSize: 12,
                        color: themeTextSub(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Playlists page: vertical list with counts + play/shuffle actions.
class PlaylistsScreen extends ConsumerWidget {
  final ValueChanged<String>? onOpenPlaylist;
  const PlaylistsScreen({super.key, this.onOpenPlaylist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final query = ref.watch(searchQueryProvider).trim().toLowerCase();
    if (!lib.loaded) return const Center(child: CircularProgressIndicator());
    final playlists = lib.playlists
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
        .toList();
    if (playlists.isEmpty) {
      return const Center(
        child: Text(
          'プレイリストがありません\nサイドバーの＋から作成できます',
          textAlign: TextAlign.center,
          style: TextStyle(color: kTextSub),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(title: 'プレイリスト', trailing: '${playlists.length}個'),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: playlists.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (c, i) {
              final pl = playlists[i];
              return Container(
                decoration: BoxDecoration(
                  color: themeCard(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: ThumbImage(
                    seed: pl.id,
                    mediaId: pl.mediaIds.isEmpty
                        ? null
                        : lib.byId(pl.mediaIds.first)?.id,
                    localPath: pl.mediaIds.isEmpty
                        ? null
                        : lib.byId(pl.mediaIds.first)?.localPath,
                    size: 48,
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '再生',
                        icon: const Icon(Icons.play_arrow),
                        onPressed: pl.mediaIds.isEmpty
                            ? null
                            : () {
                                showPlayerView(ref);
                                ref
                                    .read(playbackControllerProvider)
                                    .startPlaylist(pl.id, shuffle: false);
                              },
                      ),
                      IconButton(
                        tooltip: 'シャッフル再生',
                        icon: const Icon(Icons.shuffle, size: 20),
                        onPressed: pl.mediaIds.isEmpty
                            ? null
                            : () {
                                showPlayerView(ref);
                                ref
                                    .read(playbackControllerProvider)
                                    .startPlaylist(pl.id, shuffle: true);
                              },
                      ),
                    ],
                  ),
                  onTap: onOpenPlaylist == null
                      ? null
                      : () => onOpenPlaylist!(pl.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
