import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/app_state.dart';

void main() {
  test('unscoped media surfaces inherit the home image priority', () {
    expect(
      effectiveMediaImagePriority(priorities: defaultMediaImagePriorities),
      MediaImagePriority.thumbnailFirst,
    );
  });

  test(
    'playlist overrides win, while thumbnail-only surfaces stay thumbnails',
    () {
      final priorities = {
        ...defaultMediaImagePriorities,
        MediaImageContext.home: MediaImagePriority.thumbnailFirst,
      };
      expect(
        effectiveMediaImagePriority(
          priorities: priorities,
          playlistPriority: MediaImagePriority.artworkFirst.name,
        ),
        MediaImagePriority.artworkFirst,
      );
      expect(
        effectiveMediaImagePriority(
          priorities: priorities,
          playlistPriority: MediaImagePriority.artworkFirst.name,
          useArtwork: false,
        ),
        MediaImagePriority.thumbnailFirst,
      );
    },
  );

  test('playlist priority overrides media and screen priorities', () {
    expect(
      effectiveMediaImagePriority(
        priorities: defaultMediaImagePriorities,
        imageContext: MediaImageContext.album,
        playlistPriority: MediaImagePriority.artworkFirst.name,
        mediaPriority: MediaImagePriority.thumbnailFirst.name,
      ),
      MediaImagePriority.artworkFirst,
    );
    expect(
      effectiveMediaImagePriority(
        priorities: defaultMediaImagePriorities,
        imageContext: MediaImageContext.home,
        mediaPriority: MediaImagePriority.artworkFirst.name,
      ),
      MediaImagePriority.artworkFirst,
    );
  });

  test('image priorities are saved independently by screen', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(mediaImagePriorityProvider.notifier)
        .setPriority(MediaImageContext.home, MediaImagePriority.artworkFirst);

    expect(
      container.read(mediaImagePriorityProvider)[MediaImageContext.home],
      MediaImagePriority.artworkFirst,
    );
    expect(
      container.read(mediaImagePriorityProvider)[MediaImageContext.playlist],
      MediaImagePriority.thumbnailFirst,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        'yureru_media_image_priority_home',
      ),
      MediaImagePriority.artworkFirst.name,
    );
  });
}
