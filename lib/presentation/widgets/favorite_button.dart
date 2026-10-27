import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../i18n.dart';
import 'app_svg_icon.dart';

/// Library identity is shared by every view; temporary files must be saved first.
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({super.key, required this.mediaId, this.color});
  final String mediaId;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = ref.watch(
      libraryProvider.select((library) => library.byId(mediaId)),
    );
    final enabled = media != null && !media.isTemporary;
    final favorite = media?.isFavorite ?? false;
    return IconButton(
      tooltip: ref.tr(
        !enabled
            ? 'favorite_requires_save'
            : favorite
            ? 'remove_favorite'
            : 'add_favorite',
      ),
      isSelected: favorite,
      icon: AppSvgIcon(
        favorite ? 'favorite_filled' : 'favorite',
        color: favorite ? Theme.of(context).colorScheme.primary : color,
      ),
      onPressed: enabled
          ? () => ref.read(libraryProvider.notifier).toggleFavorite(mediaId)
          : null,
    );
  }
}
