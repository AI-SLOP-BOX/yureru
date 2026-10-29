# Yureru — local videos, like a music player

## Run

```sh
flutter pub get
flutter run            # iOS/Android (pick a device)
flutter run -d macos   # macOS
```

Import: Settings → Library Management → Import Videos.

## Structure

- `lib/domain/models.dart` — MediaItem (Media ID identity), Playlist (ID list), QueueBuilder
- `lib/library/` — library state and mutations; media edits share one update/persistence path and session-only media stays out of storage
- `lib/ambient/` — ambient-light settings and frame capture lifecycle, independently testable with a playback engine
- `lib/data/` — `LibraryRepository` (+Prefs impl, InMemory for tests), `VideoImporter` (progress callbacks, artist-title split), `ThumbnailService` (best-frame extraction on macOS and media_kit platforms, v3 disk cache + time sidecar, gradient fallback) + `DurationService` (cross-platform duration probe) + `SessionStore` (queue + positions)
- `lib/playback/` — `playback_engine.dart` (abstract) + `media_kit_engine.dart` (only media_kit import) + `playback_controller.dart` (Queue→engine, UI-free) + `fake_engine.dart` (tests)
- `lib/app_state.dart` — Riverpod `libraryProvider`, `queueProvider` (queue separate from playlist), `searchQueryProvider`, `viewingPlayerProvider` (player vs browse), `queueVisibleProvider`, `playerViewModeProvider` (media/image)
- `lib/presentation/` — shell (wide 3-pane / narrow fallback, shortcuts, drag splitters) / Home (+PreviewBar info panel: idle pick / playing item + duration + next-up, bottom) / PlaylistDetail (responsive artwork + track list, playing indicator, durations) / Videos (manual and automatic sort, playing indicator, queue ops, add-to-playlist, probed durations) / Settings / LibraryManagement (progress) / PlayerCard (media/image, PiP window, fullscreen) / TransportBar (centered cluster + full-width timeline, compact mode, mute memory) / QueuePanel (resizable, insertNext/append, playback history retained) / MiniPlayer / Sidebar (collapsible rail)

### Extending library features

Use `MediaItem.copyWith` and `Playlist.copyWith` for edits: omitted fields are
preserved, and explicit `null` clears nullable media fields. IDs and creation
times stay stable. When adding a media field, update the model, its copy method,
and JSON serialization together. Keep field-specific mutations in
`LibraryNotifier` and route media persistence through its shared update path.

Feature modules should import their own dependencies, without importing
`app_state.dart`. That file wires providers together and re-exports the extracted
types for existing callers. Ambient capture depends on `PlaybackEngine`, so a
new engine can participate without depending on library storage or screen code.

`test/models_test.dart` and `test/library_notifier_test.dart` cover field
preservation, clearing nullable values, playlist identity, and temporary-media
persistence. Run `flutter analyze` and `flutter test` after changes.

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
- Android release builds use the debug key for local testing unless a private
  upload key is configured. Set `YURERU_ANDROID_KEYSTORE`,
  `YURERU_ANDROID_STORE_PASSWORD`, `YURERU_ANDROID_KEY_ALIAS`, and
  `YURERU_ANDROID_KEY_PASSWORD` in the build environment for signed releases.

## Tests

`flutter test`

## Release builds

Pushing to `main` runs `.github/workflows/release.yml` on GitHub Actions and
uploads macOS, Windows, Linux, Android APK, and unsigned iOS build artifacts
to that workflow run. Pushing a `v*` tag also attaches those files to a GitHub
Release. Android uses the debug key unless release keystore secrets are
configured; the iOS IPA is unsigned and cannot be installed without signing.

### Immersive player

While playing, use the Immersive mode button in the player controls.
The view pairs video or artwork with large synchronized lyrics, arranging them
side by side on wide or short landscape windows and vertically on phones.
Toggle artwork/video, open the volume controls, or hide lyrics with the buttons
at the top. Shuffle and repeat use the same controls and queue state as the
standard transport bar. Muting remembers the last audible volume across layouts. Playback
controls fade after three idle seconds while playing and reappear on pointer
movement or touch; they stay visible when accessibility navigation is enabled.
Use the top-left close button, Escape, or the system back action to return to
the previous layout without reloading playback.

### Automatic volume adjustment

Settings → Audio → Reduce volume differences enables real-time loudness
normalization for playback on iOS, macOS, Windows, Linux, and Android. It is off
by default and saved between launches. The saved preference is applied before
session playback resumes. Processing does not rewrite files or change the
manual volume/mute level, and may change dynamics within a track.

The effect uses FFmpeg's [loudnorm](https://ffmpeg.org/ffmpeg-filters.html#loudnorm)
through a labeled [mpv audio filter](https://mpv.io/manual/stable/#audio-filters),
so toggling it preserves other effects. iOS uses the same processing backend
when normalization is enabled; ordinary playback can still use the native
AVPlayer backend. Processing failures retain the previous setting and show an
error instead of reporting a successful change.

### Favorites

Favorite saved tracks from the video-list row menu or the regular/immersive
player. The heart button in the video-list header filters favorites while
preserving search and artist filters; playing from that view queues only its
visible results. Clear the heart filter even when the list is empty. Global
search result navigation clears the filter so its target remains reachable.
Favorite marks persist between launches and through metadata edits. Temporary
files must be saved to the library first; existing library entries default to
not favorited. Manual reordering is disabled in the filtered view so subset
positions cannot change the wrong entries in the full library.

### Playback history

Choose Recently played in the video-list sort menu. Played tracks appear first,
most recent first; never-played tracks follow by import date. This combines with
favorites, search and artist filters without changing the active queue.

History is stored per saved media item after a successful playback load or
resume. Paused session restoration, failed loads and temporary files do not
create history. Metadata edits preserve history, and history storage failures
do not interrupt playback. Settings → Library → Clear playback history asks for
confirmation and clears only the timestamps, preserving tracks, favorites,
playlists and resume positions.

### Home collections

Home shows nonempty Recently played and Favorites shelves alongside Recently
added. Each shelf previews up to ten tracks. Playing from Favorites or Recently
played queues the full collection in its displayed order, even when it contains
more than ten tracks. Recently added queues its complete collection in newest-first order.

See all opens the matching video-list filter/sort and clears unrelated artist
and search filters. Empty shelves are hidden, and searching Home replaces the
shelves with matching results. The shared `MediaShelf` widget keeps card layout
consistent across these collections.

### macOS system playback controls

On macOS, the existing playback engine publishes the current title, artist,
selected artwork, position and playback rate to the system Now Playing panel.
Play/pause, next/previous and position changes from macOS use the same controller
and queue as the app, including while the app is in the background. Empty queues
and app termination clear the published state. Progress updates are coalesced
and limited to one per second; metadata and play-state changes update immediately.

`SystemMediaSession` is the tested Dart platform boundary, with Riverpod wiring
in `system_media_provider.dart` and the native implementation in
`macos/Runner/SystemMediaControls.swift`. It uses Apple's
[Now Playing information center](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
and remote commands. This integration currently targets macOS; the native
bridge is optional and its absence does not block playback on other platforms.

### スリープタイマー

通常のプレイヤーと没入モードから、15・30・60分後、または現在の曲の終了時に一時停止できます。曲の終了時の停止はリピートより優先します。手動で別の曲へ移動すると曲終了時のタイマーは解除され、時間指定のタイマーは継続します。キューが空になると解除し、アプリを再起動した場合は引き継ぎません。時間指定で停止した場合は再生位置を保存します。

### Album and artist browsing

Library now has Overview, Albums, and Artists sections. Album collections group
saved tracks by album title and album artist (falling back to the track artist),
so identically titled albums by different artists remain separate. Albums play in disc-number order (an unset disc number means disc one), then
track-number order. Unnumbered tracks follow numbered tracks within each disc
and are sorted by title.
Artist collections include each credited collaborator, using the same credit
splitting as the existing creator filters. Missing credits and album titles
remain accessible in Unknown artist / Unknown album groups.

Open a collection to play it, shuffle it, choose an individual track, favorite
tracks, or edit their information. Selecting a track queues its entire collection,
even when a search hides other tracks. Searches match collection names, artist
credits, and track titles. Metadata edits update collections immediately.
Temporary playback items are excluded.

The information editor supports album title, album artist, positive disc numbers,
and positive track numbers; clear a field to remove its value. Existing libraries load with these
fields unset. This change does not extract album tags from imported files;
set them through the information editor. Collection grids and track lists create
visible entries lazily, and grouping is cached until the library changes.

### Bulk information editing

Open an album or artist collection and choose Select tracks. Select individual
rows or select/deselect the currently visible search results. The selected count
includes previously selected tracks hidden by a later search. Editing and
selection do not change playback or the queue.

The bulk editor can change album title, album artist, and track artist. Only
checked fields are applied; unchecked fields preserve each track's own value.
A checked empty field explicitly clears its value. Shared values are prefilled,
but no field is checked by default. Track numbers are preserved unless sequential numbering is enabled. Favorites,
lyrics, artwork, and media identity are preserved. Temporary files and missing IDs are ignored.

A batch uses one repository save. If that save throws, the editor retains inputs
and shows a retryable error; the batch's visible changes are rolled back when no
other media edit has superseded them. Successful edits return to the collection
grid so renamed or merged collections can be found immediately.

### Multi-disc albums and sequential numbering

The information editor and bulk editor can set a positive disc number or clear
it. Existing libraries default to an unset disc number, treated as disc one
for album ordering. Albums with discs beyond disc one show disc labels beside
the track credits.

In the bulk editor, enable Number tracks sequentially and enter a positive
starting number. Numbers follow the displayed collection order of selected
tracks, not selection click order or import order. The editor previews the first
five assignments. Existing track numbers are replaced only when this option is
enabled; other tracks are untouched. Duplicate, missing, and temporary IDs do
not introduce gaps in numbering. Numbering continues across the selected tracks;
select one disc at a time to restart each disc at one.

### Library readability

Library sections wrap instead of hiding destinations off-screen. Compact windows
show text labels; wider windows also show SVG icons. Collection details separate
artwork, title, artist, track count, and primary playback actions. Track rows use
a labeled overflow menu for favorites and information editing, leaving room for
long titles. Favorite status remains visible beside the title.

Selection mode keeps its count and edit actions at the bottom while the track
list scrolls. Select visible and Deselect visible affect only current search
results; a separate message reports selected tracks hidden by search. Finishing
selection clears the selection without changing playback. Empty search results
include a clear-search action. Bulk editing distinguishes mixed values, unchanged
fields, and fields applied to every selected track.

### Video-list navigation

The video list labels its Favorites filter and current sort order. Active artist
and search filters appear as removable chips; Clear filters resets all three
filters while preserving the selected sort order. Search also matches album
titles. Empty filtered results offer the same reset action. Manual ordering
includes a press-and-hold hint and remains disabled while the list is filtered.

Compact list rows prioritize artwork, title, artist, and the action menu; wider
rows also show index and duration columns. Favorites remain visible, and the
current queue item has a distinct highlight and accessibility label. List icons
use SVG assets. Row height adapts to enlarged text; search-result navigation uses
that height to scroll distant results into view.

### Settings navigation

Settings keeps category buttons above its scrollable content: All, Display,
Audio, Library, and App. Selecting a category shows only that group and resets
the content scroll position without changing preference values. Each group
includes a short explanation and SVG icon.

Display keeps theme and ambient-light enablement visible; lighting geometry,
intensity, and update rate live under expandable Lighting details. Sliders show
the label and current percentage above a full-width control. Update rate uses
a full-width selector with an explicit FPS label. Language selection also uses
the available width, and language names no longer contain flag emoji.

### Leaving immersive mode

Immersive mode keeps a labeled Back to standard view button and mode indicator
visible even after optional playback controls fade out. Compact screens place
the return action above the secondary controls. The video/artwork selector shows
the current view and offers explicitly labeled, checked menu options. The
regular desktop player also labels the immersive entry button. Switching these
views continues to preserve playback, queue, and position without reloading
the source.

### Neutral theme

The shared theme uses neutral gray canvases, panels, cards, borders, and text
for both dark and light appearances. Selected surfaces use a distinct gray
container; primary actions use light buttons in dark mode and dark buttons in
light mode. The Material color scheme is monochrome to avoid generated color
tints. The wave logo and missing-artwork placeholders are also neutral, with
no colored glow. Chips, menus, navigation, dialogs, fields, and buttons use the same
color scheme and a consistent corner scale. Subtitle and duration colors adapt
to the active theme instead of reusing dark-only colors on light backgrounds.

Persistent controls share a clipped `FrostedPanel`: the top bar, home preview,
transport, queue/lyrics panel, compact mini player, and compact navigation use
neutral translucent glass with a subtle highlight and backdrop blur. Queue rows
share one panel-level blur. High-contrast mode uses an opaque surface instead.
Glass contrast tests also check secondary text over black and white backdrops.

Contrast tests cover primary and secondary body text on the main surfaces,
selected labels, and primary button labels at a minimum ratio of 4.5:1.

### Home clarity

Home shelf height follows the card artwork and scaled text instead of leaving
a fixed empty band below each row. Cards show title and artist (or duration
when the artist is missing). Touch layouts keep a small play cue visible, and
keyboard focus also reveals the play affordance. Missing artwork uses a neutral
SVG music-note placeholder.

The home count reports saved items. Empty playlist guidance is kept in the
sidebar instead of repeated below the shelves. The playlist grid no longer
reserves extra space for a footer that already owns its layout space.
The footer labels its idle suggestion Start listening and its active queue item
Current track; Open player opens the player rather than a file picker.
Recently added playback now follows its displayed newest-first collection.
