import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../platform/window_utils.dart';
import '../theme.dart';

/// Top bar: logo-home + global search + window/panel icon actions.
class TopBar extends ConsumerStatefulWidget {
  final bool queueVisible;
  final VoidCallback onToggleQueue;
  final VoidCallback onLogoHome;
  final VoidCallback onOpenSearch;
  final ValueChanged<String> onSubmitSearch;
  const TopBar({
    super.key,
    required this.queueVisible,
    required this.onToggleQueue,
    required this.onLogoHome,
    required this.onOpenSearch,
    required this.onSubmitSearch,
  });

  @override
  ConsumerState<TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<TopBar> {
  late final TextEditingController _ctrl;
  late final FocusNode _searchFocusNode;
  Timer? _debounceTimer;
  bool _searchHasFocus = false;
  bool _showExpandedSearchOnVeryCompact = false;
  bool _backButtonPressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: ref.read(searchQueryProvider));
    _searchFocusNode = FocusNode();
    _searchFocusNode.addListener(_onFocusChange);
    _searchFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        if (_ctrl.text.isNotEmpty) {
          _clearSearch();
        } else {
          _searchFocusNode.unfocus();
          if (mounted && _showExpandedSearchOnVeryCompact) {
            setState(() => _showExpandedSearchOnVeryCompact = false);
          }
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  void _onFocusChange() {
    if (mounted && _searchHasFocus != _searchFocusNode.hasFocus) {
      final losingFocus = !_searchFocusNode.hasFocus;
      setState(() {
        _searchHasFocus = _searchFocusNode.hasFocus;
        if (losingFocus && _ctrl.text.isEmpty) {
          _showExpandedSearchOnVeryCompact = false;
        }
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _searchFocusNode.removeListener(_onFocusChange);
    _searchFocusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        ref.read(searchQueryProvider.notifier).state = v;
      }
    });
  }

  Future<void> _enterPictureInPicture() async {
    await setPictureInPictureWindow(true);
    if (mounted) ref.read(pictureInPictureProvider.notifier).state = true;
  }

  void _onSearchSubmitted(String v) {
    _debounceTimer?.cancel();
    ref.read(searchQueryProvider.notifier).state = v;
    _searchFocusNode.unfocus();
    if (v.trim().isNotEmpty) widget.onSubmitSearch(v.trim());
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _ctrl.clear();
    ref.read(searchQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Listen to external searchQueryProvider changes safely:
    // Protect IME composition and user active editing from being clobbered or resetting cursor.
    ref.listen<String>(searchQueryProvider, (previous, next) {
      _debounceTimer?.cancel();
      // If user is actively typing in the field or IME is composing, do not overwrite controller
      if (_searchFocusNode.hasFocus || _ctrl.value.isComposingRangeValid) {
        return;
      }
      if (_ctrl.text != next) {
        _ctrl.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    });

    final iconColor = isDark ? Colors.white70 : Colors.black87;
    final searchBgColor = isDark
        ? kPanelAlt
        : Colors.black.withValues(alpha: 0.05);
    final searchBorderColor = _searchHasFocus
        ? (isDark
              ? kAccentLight.withValues(alpha: 0.7)
              : kAccent.withValues(alpha: 0.6))
        : (isDark ? kGlassBorder : const Color(0x1A000000));

    final hintColor = isDark ? kTextMuted : Colors.black45;
    final inputTextColor = isDark ? kTextPrimary : Colors.black87;
    final shortcutBadgeBg = isDark
        ? kGlassHighlight
        : Colors.black.withValues(alpha: 0.06);
    final shortcutTextColor = isDark ? kTextSub : Colors.black54;

    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    final isDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    final canPictureInPicture = ref.watch(
      queueProvider.select((queue) => queue.hasCurrent),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 740;
        final isVeryCompact = constraints.maxWidth < 560;

        // In very compact mode:
        // When not expanded: show search icon button.
        // When expanded: show search bar full width (hide other buttons to prevent overflow).
        final isCompactExpanded =
            isVeryCompact && _showExpandedSearchOnVeryCompact;
        final collapseSearchField =
            isVeryCompact &&
            !_showExpandedSearchOnVeryCompact &&
            _ctrl.text.isEmpty &&
            !_searchHasFocus;

        void closeCompactSearch() {
          _searchFocusNode.unfocus();
          _clearSearch();
          if (mounted && _showExpandedSearchOnVeryCompact) {
            setState(() => _showExpandedSearchOnVeryCompact = false);
          }
        }

        final content = CallbackShortcuts(
          bindings: {
            // ⌘K / Ctrl+K: Global search palette (SearchOverlay)
            SingleActivator(
              LogicalKeyboardKey.keyK,
              meta: isMacOS,
              control: !isMacOS,
            ): widget.onOpenSearch,
            // ⌘F / Ctrl+F: Focus the in-page search bar
            // Scoped: Only trigger if the current route is active (prevents hijacking modal / sub-view Ctrl+F)
            SingleActivator(
              LogicalKeyboardKey.keyF,
              meta: isMacOS,
              control: !isMacOS,
            ): () {
              if (ModalRoute.of(context)?.isCurrent != true) return;
              if (isVeryCompact) {
                setState(() => _showExpandedSearchOnVeryCompact = true);
              }
              _searchFocusNode.requestFocus();
            },
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                if (!isCompactExpanded) ...[
                  Builder(
                    builder: (bContext) => IconButton(
                      tooltip: Scaffold.maybeOf(bContext)?.hasDrawer == true
                          ? 'メニューを開く'
                          : (collapsed ? 'サイドバーを表示' : 'サイドバーを隠す'),
                      icon: Icon(
                        Icons.menu_rounded,
                        size: 22,
                        color: iconColor,
                      ),
                      onPressed: () {
                        final scaffold = Scaffold.maybeOf(bContext);
                        if (scaffold != null && scaffold.hasDrawer) {
                          scaffold.openDrawer();
                        } else {
                          ref.read(sidebarCollapsedProvider.notifier).state =
                              !collapsed;
                        }
                      },
                    ),
                  ),
                  if (constraints.maxWidth >= 340) ...[
                    const SizedBox(width: 4),
                    Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: widget.onLogoHome,
                        child: const Tooltip(
                          message: 'ライブラリに戻る',
                          child: Padding(
                            padding: EdgeInsets.all(4),
                            child: _TopBarLogo(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ] else ...[
                  // Back button when search is expanded full-width on very small screens
                  IconButton(
                    tooltip: '検索を閉じる (Esc)',
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      size: 22,
                      color: iconColor,
                    ),
                    onPressed: closeCompactSearch,
                  ),
                  const SizedBox(width: 4),
                ],

                // Center Search Area: either collapsed icon or prominent search pill
                if (collapseSearchField) ...[
                  IconButton(
                    tooltip: '検索',
                    icon: Icon(
                      Icons.search_rounded,
                      size: 22,
                      color: iconColor,
                    ),
                    onPressed: () {
                      setState(() => _showExpandedSearchOnVeryCompact = true);
                      _searchFocusNode.requestFocus();
                    },
                  ),
                  const Spacer(),
                ] else ...[
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 580),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _searchFocusNode.requestFocus(),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Fixed static blur layer with opacity transition:
                              // Avoids expensive per-frame Gaussian blur re-rasterization spikes on GPU
                              Positioned.fill(
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOut,
                                  opacity: _searchHasFocus ? 1.0 : 0.0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(24),
                                      boxShadow: [
                                        BoxShadow(
                                          color: kAccent.withValues(
                                            alpha: isDark ? 0.28 : 0.18,
                                          ),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                height: 42,
                                decoration: BoxDecoration(
                                  color: searchBgColor,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: searchBorderColor,
                                    width: _searchHasFocus ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 14,
                                        right: 10,
                                      ),
                                      child: Icon(
                                        Icons.search_rounded,
                                        size: 20,
                                        color: isDark
                                            ? kTextSub
                                            : Colors.black45,
                                      ),
                                    ),
                                    Expanded(
                                      child: Semantics(
                                        label: 'ライブラリ内検索',
                                        textField: true,
                                        child: TextField(
                                          controller: _ctrl,
                                          focusNode: _searchFocusNode,
                                          onChanged: _onSearchChanged,
                                          textInputAction:
                                              TextInputAction.search,
                                          onSubmitted: _onSearchSubmitted,
                                          contextMenuBuilder:
                                              (context, editableTextState) {
                                                return AdaptiveTextSelectionToolbar.editableText(
                                                  editableTextState:
                                                      editableTextState,
                                                );
                                              },
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: inputTextColor,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: isVeryCompact
                                                ? '検索...'
                                                : '曲、動画、プレイリストを検索...',
                                            hintStyle: TextStyle(
                                              fontSize: 14,
                                              color: hintColor,
                                            ),
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  vertical: 10,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Localized Consumer: only rebuilds this trailing icon button on empty/non-empty change
                                    Consumer(
                                      builder: (context, ref, _) {
                                        final hasText = ref.watch(
                                          searchQueryProvider.select(
                                            (q) => q.isNotEmpty,
                                          ),
                                        );
                                        if (hasText) {
                                          return IconButton(
                                            tooltip: 'クリア (Esc)',
                                            splashRadius: 18,
                                            icon: Icon(
                                              Icons.clear_rounded,
                                              size: 18,
                                              color: isDark
                                                  ? kTextSub
                                                  : Colors.black54,
                                            ),
                                            onPressed: _clearSearch,
                                          );
                                        }
                                        if (isCompact) {
                                          return const SizedBox.shrink();
                                        }
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          child: Tooltip(
                                            message: '全体検索',
                                            child: InkWell(
                                              onTap: widget.onOpenSearch,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: shortcutBadgeBg,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: shortcutBadgeBg,
                                                  ),
                                                ),
                                                child: Text(
                                                  isMacOS ? '⌘ K' : 'Ctrl+K',
                                                  style: TextStyle(
                                                    fontFamily: isMacOS
                                                        ? '.AppleSystemUIFont'
                                                        : defaultTargetPlatform ==
                                                              TargetPlatform
                                                                  .windows
                                                        ? 'Segoe UI Variable Text'
                                                        : null,
                                                    fontFamilyFallback: const [
                                                      'Segoe UI',
                                                      'Roboto',
                                                      'Cantarell',
                                                      'Noto Sans',
                                                      'sans-serif',
                                                    ],
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: shortcutTextColor,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
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
                ],

                // Hide other action icons when search is expanded full-width on tiny screens (<560px)
                if (!isCompactExpanded) ...[
                  const SizedBox(width: 8),

                  IconButton(
                    tooltip: !isDark ? 'ダークモードに切り替え' : 'ライトモードに切り替え',
                    icon: Icon(
                      !isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      size: 20,
                      color: iconColor,
                    ),
                    onPressed: () =>
                        ref.read(themeModeProvider.notifier).toggle(),
                  ),
                  if (isDesktop && !isCompact)
                    IconButton(
                      tooltip: 'ピクチャ・イン・ピクチャ',
                      icon: Icon(
                        Icons.picture_in_picture_alt_rounded,
                        size: 21,
                        color: iconColor,
                      ),
                      onPressed: canPictureInPicture
                          ? _enterPictureInPicture
                          : null,
                    ),
                  if (isDesktop && !isCompact)
                    IconButton(
                      tooltip: 'フルスクリーン',
                      icon: Icon(
                        Icons.fullscreen_rounded,
                        size: 26,
                        color: iconColor,
                      ),
                      onPressed: toggleFullscreen,
                    ),
                ],
              ],
            ),
          ),
        );

        // When expanded full width on compact screens:
        // 1. Trap focus within an active FocusScope with canRequestFocus: true
        // 2. Intercept mouse back button (kBackMouseButton) on pointer release (OS-standard Up event)
        if (isCompactExpanded) {
          return Listener(
            onPointerDown: (event) {
              if ((event.buttons & kBackMouseButton) != 0) {
                _backButtonPressed = true;
              }
            },
            onPointerUp: (event) {
              if (_backButtonPressed) {
                _backButtonPressed = false;
                closeCompactSearch();
              }
            },
            onPointerCancel: (_) => _backButtonPressed = false,
            child: FocusScope(
              autofocus: true,
              canRequestFocus: true,
              child: content,
            ),
          );
        }

        return content;
      },
    );
  }
}

/// Static, const-constructible logo widget to prevent per-build heap allocations.
class _TopBarLogo extends StatelessWidget {
  const _TopBarLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Image.asset(
        'assets/yureru_logo.png',
        width: 32,
        height: 32,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.music_note_rounded, size: 28, color: kAccentLight),
      ),
    );
  }
}
