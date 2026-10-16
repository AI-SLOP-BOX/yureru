# yureru — local videos, like a music player

## Run

```sh
flutter pub get
flutter run            # iOS/Android (pick a device)
flutter run -d macos   # macOS
```

Import: Settings → Library Management → Import Videos.

## Structure

- `lib/domain/models.dart` — MediaItem (Media ID identity), Playlist (ID list), QueueBuilder
- `lib/data/` — `LibraryRepository` (+Prefs impl, InMemory for tests), `VideoImporter` (progress callbacks, artist-title split), `ThumbnailService` (native best-of-8 textured-bright frame, v3 disk cache + time sidecar, gradient fallback) + `DurationService` (native metadata probe) + `SessionStore` (queue + positions)
- `lib/playback/` — `playback_engine.dart` (abstract) + `media_kit_engine.dart` (only media_kit import) + `playback_controller.dart` (Queue→engine, UI-free) + `fake_engine.dart` (tests)
- `lib/app_state.dart` — Riverpod `libraryProvider`, `queueProvider` (queue separate from playlist), `searchQueryProvider`, `viewingPlayerProvider` (player vs browse), `queueVisibleProvider`, `playerViewModeProvider` (media/image)
- `lib/presentation/` — shell (wide 3-pane / narrow fallback, shortcuts, drag splitters) / Home (+PreviewBar info panel: idle pick / playing item + duration + next-up, bottom) / PlaylistDetail (responsive artwork + track list, playing indicator, durations) / Videos (manual and automatic sort, playing indicator, queue ops, add-to-playlist, probed durations) / Settings / LibraryManagement (progress) / PlayerCard (media/image, PiP window, fullscreen) / TransportBar (centered cluster + full-width timeline, compact mode, mute memory) / QueuePanel (resizable, insertNext/append, playback history retained) / MiniPlayer / Sidebar (collapsible rail)

## Behavior

- Center shows the player OR browse pages, never stacked. Fresh playback
  enters the player (+queue); nav taps return to browsing; auto-advance
  never steals the screen. Returning via transport/mini-player never
  reopens a user-closed queue. Transport bar hides when idle.
- Session restore: the last active video's position persists; launch preloads
  it paused at the last position (no autoplay).
- Cmd/Ctrl+K global search palette (videos + playlists); TopBar field
  filters only the current list. Logo (always top-left) goes home.
- Media/image toggle hides video only; engine (position, speed, volume,
  queue, shuffle, repeat) untouched.
- Native macOS channel (`yureru/media_picker`): pickVideos / pickFolder /
  toggleFullscreen / makeThumbnail (best-of-N) / probeDuration.

## Tests

`flutter test`
