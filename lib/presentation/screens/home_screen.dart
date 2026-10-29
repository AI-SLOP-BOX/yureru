import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/models.dart';
import '../../library/media_order.dart';
import '../../domain/creator_names.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';
import '../../library/media_collections.dart';
import 'collection_browser.dart';
import '../widgets/app_svg_icon.dart';
import '../theme.dart';
import '../widgets/page_header.dart';
import '../widgets/duration_text.dart';
import '../widgets/thumb_image.dart';
import '../widgets/media_shelf.dart';

/// Library home: playlist grid (player card sits above this in the shell).
class HomeScreen extends ConsumerStatefulWidget {
  final ValueChanged<String>? onOpenPlaylist;
  final VoidCallback? onOpenVideos;
  const HomeScreen({super.key, this.onOpenPlaylist, this.onOpenVideos});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _section = 0;

  Widget _sections() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
    child: LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in [
            (0, 'library_overview', 'collection_home'),
            (1, 'albums', 'collection_album'),
            (2, 'artists', 'collection_artist'),
          ])
            ChoiceChip(
              label: Text(ref.tr(entry.$2)),
              avatar: constraints.maxWidth >= 480
                  ? AppSvgIcon(entry.$3, size: 18)
                  : null,
              selected: _section == entry.$1,
              showCheckmark: false,
              onSelected: (_) => setState(() => _section = entry.$1),
            ),
        ],
      ),
    ),
  );

  final ScrollController _libraryScrollController = ScrollController();

  @override
  void dispose() {
    _libraryScrollController.dispose();
    super.dispose();
  }

  void _playCollection(List<MediaItem> items, MediaItem selected) {
    final order = items.map((item) => item.id).toList();
    final index = order.indexOf(selected.id);
    if (index < 0) return;
    showPlayerView(ref);
    ref.read(queueProvider.notifier).start(order, shuffle: false);
    ref.read(queueProvider.notifier).jumpTo(index);
    ref.read(playbackControllerProvider).openCurrent();
  }

  void _openCollection({required bool favorites, required VideosSort sort}) {
    ref.read(favoritesOnlyProvider.notifier).state = favorites;
    ref.read(videosSortProvider.notifier).state = sort;
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(videoCreatorFilterProvider.notifier).state = null;
    widget.onOpenVideos?.call();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final lib = ref.watch(libraryProvider);
    final query = ref.watch(searchQueryProvider).trim().toLowerCase();
    if (!lib.loaded) return const Center(child: CircularProgressIndicator());
    if (_section != 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(title: ref.tr('library')),
          _sections(),
          Expanded(
            child: CollectionBrowser(
              kind: _section == 1
                  ? CollectionKind.albums
                  : CollectionKind.artists,
            ),
          ),
        ],
      );
    }
    final playlists = lib.playlists
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
        .toList();
    final matchingSongs = query.isEmpty
        ? <MediaItem>[]
        : lib.savedMedia.where((m) {
            final t = m.title.toLowerCase();
            final a = (m.artist ?? '').toLowerCase();
            return t.contains(query) ||
                a.contains(query) ||
                (m.album ?? '').toLowerCase().contains(query);
          }).toList();

    if (playlists.isEmpty && lib.savedMedia.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.video_library_outlined,
                size: 56,
                color: themeTextSub(context),
              ),
              SizedBox(height: 14),
              Text(
                ref.tr('empty_library'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                ref.tr('import_video_desc'),
                textAlign: TextAlign.center,
                style: TextStyle(color: themeTextSub(context), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    final recentlyPlayed =
        lib.savedMedia.where((item) => item.lastPlayedAt != null).toList()
          ..sort(compareRecentlyPlayed);
    final favorites = lib.savedMedia.where((item) => item.isFavorite).toList();
    final recentlyAdded = [...lib.savedMedia]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // The middle scrolls: header + preview are fixed, so CJK line-height
    // variance (the classic 1px Column overflow) can never break this page.
    final headerTrailing = query.isNotEmpty
        ? '${ref.tracksCount(matchingSongs.length)} • ${ref.playlistsCount(playlists.length)}'
        : '${ref.tracksCount(lib.savedMedia.length)}${playlists.isEmpty ? '' : ' • ${ref.playlistsCount(playlists.length)}'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(title: ref.tr('library'), trailing: headerTrailing),
        _sections(),
        Expanded(
          child: Scrollbar(
            controller: _libraryScrollController,
            thumbVisibility: true,
            interactive: true,
            child: CustomScrollView(
              controller: _libraryScrollController,
              primary: false,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (query.isEmpty) ...[
                  if (recentlyPlayed.isNotEmpty)
                    SliverToBoxAdapter(
                      child: MediaShelf(
                        key: const ValueKey('home-recently-played'),
                        title: ref.tr('recently_played'),
                        items: recentlyPlayed,
                        seeAllLabel: ref.tr('see_all'),
                        onPlay: (media) =>
                            _playCollection(recentlyPlayed, media),
                        onSeeAll: widget.onOpenVideos == null
                            ? null
                            : () => _openCollection(
                                favorites: false,
                                sort: VideosSort.recentlyPlayed,
                              ),
                      ),
                    ),
                  if (favorites.isNotEmpty)
                    SliverToBoxAdapter(
                      child: MediaShelf(
                        key: const ValueKey('home-favorites'),
                        title: ref.tr('favorites'),
                        items: favorites,
                        seeAllLabel: ref.tr('see_all'),
                        onPlay: (media) => _playCollection(favorites, media),
                        onSeeAll: widget.onOpenVideos == null
                            ? null
                            : () => _openCollection(
                                favorites: true,
                                sort: VideosSort.manual,
                              ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: MediaShelf(
                      key: const ValueKey('home-recently-added'),
                      title: ref.tr('home_recently_added'),
                      items: recentlyAdded,
                      seeAllLabel: ref.tr('see_all'),
                      onPlay: (media) => _playCollection(recentlyAdded, media),
                      onSeeAll: widget.onOpenVideos == null
                          ? null
                          : () => _openCollection(
                              favorites: false,
                              sort: VideosSort.newestFirst,
                            ),
                    ),
                  ),
                ],

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
                            ref.tracksCount(matchingSongs.length),
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
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        child: Text(
                          ref.tr('not_found'),
                          style: TextStyle(
                            color: themeTextSub(context),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final m = matchingSongs[index];
                          final artistText = formatCreatorNames(m.artist);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: themeCard(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: themeBorder(context)),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 2,
                                ),
                                leading: ThumbImage(
                                  seed: m.id,
                                  mediaId: m.id,
                                  localPath: m.localPath,
                                  imageContext: MediaImageContext.home,
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
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: themeTextSub(context),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '• ',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: themeTextSub(context),
                                      ),
                                    ),
                                    DurationText(
                                      mediaId: m.id,
                                      localPath: m.localPath,
                                      durationMs: m.durationMs,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: themeTextSub(context),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  tooltip: ref.tr('play'),
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
                                    ref
                                        .read(queueProvider.notifier)
                                        .jumpTo(index);
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
                                  ref
                                      .read(queueProvider.notifier)
                                      .jumpTo(index);
                                  ref
                                      .read(playbackControllerProvider)
                                      .openCurrent();
                                },
                              ),
                            ),
                          );
                        }, childCount: matchingSongs.length),
                      ),
                    ),
                ],

                // Empty playlist guidance already lives in the sidebar.
                if (playlists.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                      child: Text(
                        query.isEmpty
                            ? ref.tr('playlists')
                            : ref.playlistsCount(playlists.length),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
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
                          onOpen: widget.onOpenPlaylist == null
                              ? null
                              : () => widget.onOpenPlaylist!(pl.id),
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
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaylistCard extends ConsumerStatefulWidget {
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
  ConsumerState<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends ConsumerState<_PlaylistCard> {
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
              ? (isDark ? kCardHover : const Color(0xFFEBEBEB))
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
                              imageContext: MediaImageContext.playlist,
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
                      ref.tracksCount(widget.count),
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
