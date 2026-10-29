import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/app_state.dart';

void main() {
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
