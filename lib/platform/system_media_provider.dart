import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_state.dart';
import '../playback/playback_controller.dart';
import 'system_media_session.dart';

final systemMediaSessionProvider = Provider<SystemMediaSession?>((ref) {
  if (!Platform.isMacOS) return null;
  final engine = ref.watch(engineProvider);
  final controller = ref.read(playbackControllerProvider);
  late final SystemMediaSession session;
  void publish() {
    final queue = ref.read(queueProvider);
    session.update(
      media: ref.read(libraryProvider).byId(queue.currentId ?? ''),
      snapshot: engine.snapshot,
      rate: queue.speed,
      canNext:
          queue.queue.length > 1 &&
          (queue.repeat != 'off' || queue.index < queue.queue.length - 1),
      canPrevious:
          queue.queue.length > 1 && (queue.repeat != 'off' || queue.index > 0),
    );
  }

  session = SystemMediaSession(
    engine: engine,
    play: () async {
      if (!engine.snapshot.isPlaying) await controller.toggle();
    },
    pause: () async {
      if (engine.snapshot.isPlaying) await controller.toggle();
    },
    toggle: controller.toggle,
    next: controller.playNext,
    previous: controller.playPrev,
    seek: controller.seekTo,
    refresh: publish,
  );
  ref.listen(queueProvider, (_, _) => publish());
  ref.listen(libraryProvider, (_, _) => publish());
  final subscription = engine.snapshots.listen(
    (_) => publish(),
    onError: (_) {},
  );
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(session.dispose());
  });
  publish();
  return session;
});
