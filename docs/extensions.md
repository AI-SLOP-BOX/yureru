# Yureru extensions (API v1)

Extensions are `.yureru` ZIP packages. They run in an embedded JavaScript
runtime; they do not run as Dart code and do not receive direct Flutter, file,
or network access. The app owns the event dispatch and validates data returned
by extensions.

## Host API

`library.write.mediaImport` runs once for a batch of newly imported items
before they are saved. The hook receives `{ items: [{ title, artist, album }] }`
and may return the same array with those fields normalized or enriched. Return
the input unchanged to do nothing.
The user must grant **Modify library information** for this hook to run.
Invalid output is ignored and an extension error never cancels an import.

Extensions can also add declarative screens and actions inside Yureru.
The app renders the declared components itself; extensions cannot inject
Flutter/Dart code or access the filesystem, network, shell, or native APIs.
This keeps the plugin surface cross-platform while allowing the host API to
grow to cover more app features.

```json
{
  "apiVersion": 1,
  "id": "example.title-cleanup",
  "name": "Title cleanup",
  "version": "1.0.0",
  "description": "Cleans up imported media titles.",
  "entrypoint": "main.js",
  "hooks": ["library.write.mediaImport", "extension.action.clean", "player.trackChanged"],
  "permissions": ["library.write", "ui.contribute", "player.control"]
}
```

```js
Yureru.on("library.write.mediaImport", ({ items }) => items.map((media) => ({
  ...media,
  title: media.title.replace(/^曲：/, ""),
})));
```

The following registers an extension page and an action button. Extension
pages open as full app screens and can contain headings, text, separators,
buttons, text inputs, multiline inputs, toggles, sliders, select menus, and
bundled images. Action hooks must be listed in the manifest, use the
`extension.action.<id>` form, and the user must grant `ui.contribute`.
Values are passed to action handlers in `context.form`. The host validates and
limits every contribution before displaying it.

```js
Yureru.register({
  settings: [
    { type: "section", label: "Import behavior" },
    { id: "enabled", label: "Clean imported titles", type: "toggle", default: true },
    { id: "prefix", label: "Leading text to remove", type: "text", default: "曲：" },
    { id: "mode", label: "Cleanup mode", type: "select", options: ["Preview", "Apply"], default: "Apply" },
    { id: "strength", label: "Match strength", type: "slider", min: 0, max: 1, default: 0.8 },
    { id: "delay", label: "Timing adjustment (seconds)", type: "number", min: -30, max: 30, default: 0 }
  ],
  commands: [
    { id: "clean", title: "Clean this track", action: "clean", icon: "library" }
  ],
  pages: [{
    id: "about-tools",
    title: "Title tools",
    blocks: [
      { type: "text", text: "Run title cleanup tools from this page." },
      { type: "input", id: "prefix", label: "Leading text", value: "曲：" },
      { type: "multiline", id: "rules", label: "Rules", value: "One rule per line" },
      { type: "toggle", id: "enabled", label: "Enable cleanup", value: true },
      { type: "slider", id: "strength", label: "Match strength", min: 0, max: 1, value: 0.8 },
      { type: "select", id: "mode", label: "Mode", options: ["Preview", "Apply"], value: "Preview" },
      { type: "image", src: "assets/example.png", alt: "Example preview" },
      { type: "divider" },
      { type: "button", label: "Show status", action: "clean" }
    ]
  }]
});

Yureru.on("extension.action.clean", (context) => {
  // context.media identifies the track whose menu was opened.
  // context.settings contains values saved from Settings → Extension settings.
  // Return a short status string for the host to show to the user.
  return "Ready";
});

Yureru.on("player.trackChanged", ({ mediaId, isPlaying }) => {
  // Player event hooks may return host commands, subject to their permissions.
});
```

Declared `settings` are added directly under Settings → Extension settings.
Supported types are `toggle`, `select`, `slider`, bounded `number`, `text`,
`multiline`, and `color`. Add `{ type: "section", label: "..." }` entries to
group related settings. Values are saved per extension and are available to action and import
hooks as `context.settings`. The user must grant both `ui.contribute` and
`extension.storage`; revoking storage leaves those settings visible but locked.
Color values use `#RRGGBB` or `#AARRGGBB`.
Commands are available from the Extensions screen and from a track's context
menu. Track actions receive `context.source: "track.menu"` and a metadata-only
`context.media` object. The track menu supports player and queue commands plus
favorite, title/artist metadata, and playlist add/remove operations. Extensions
can also subscribe to `player.trackChanged` and `player.playbackChanged`; event
hooks receive the current media ID and play state, and may return
permission-checked player or queue commands.

Place `manifest.json` and `main.js` at the package root. Optional files may be
placed under `assets/`. The app rejects other paths, symbolic links, packages
over 20 MB, expanded contents over 32 MB, and packages with more than 80 files.
JavaScript is limited to 500 ms, 16 MB of runtime memory, and a 256 KB stack.
The working example is in `examples/extensions/title-cleanup/`; zip those two
files into a `.yureru` file to install it.

An action hook may also read/write the extension's own small JSON storage when
the user grants `extension.storage`. The event then includes `storage` and
`settings` objects; return `{ storage: updatedObject, result: "message" }` to
persist custom data. Settings are stored separately under the reserved
`_settings` key. Storage is
isolated by extension ID, limited to 64 KB, and cannot address arbitrary files.

Action results can ask Yureru to perform host operations. They are checked again
against the granted permission before execution:

```js
Yureru.on("extension.action.next", () => ({
  command: { type: "player.next" },
  message: "Skipped to the next item."
}));
```

`player.control` lets an action read the current player and queue snapshot, and
allows `player.toggle`, `player.play`, `player.pause`, `player.next`,
`player.previous`, `player.seek` (`positionMs`), `player.seekRelative`
(`deltaMs`), `player.volume` (`value`, 0–1), `player.speed` (`value`, 0.25–3),
`player.shuffle` (`enabled`), `player.repeat` (`mode`: `all`, `one`, or `off`),
`queue.clear`, `queue.remove` (`from`), `queue.move` (`from`, `to`),
`queue.start` (`mediaIds`, optional `shuffle`), `queue.playNext` (`mediaId`),
and `queue.append` (`mediaId`). An action may return one command or a `commands`
array to run up to 50 operations in order. Queue and media lists are bounded;
unknown IDs are ignored.
The separate `pip.control` grant enables `pip.start` and `pip.restore` actions.
`pip.start` accepts an optional `aspectRatio`; on the custom Windows/Linux PiP
window it can also accept `width` and `height` (each clamped to a safe range).
On iOS, Android and macOS, the operating system controls the PiP window size.
For example, an action can return `{ command: { type: "pip.start", width: 640,
height: 360 } }` to open the current view in a larger desktop PiP window.
`library.read` lets actions read up to 1,000 media items and 200 playlists as
metadata only (up to 500 item IDs per playlist); local file paths are never
exposed. `library.write` allows `library.favorite` (`mediaId`),
`library.setFavorite` (`mediaId`, `value`), `library.metadata` (`mediaId`,
optional `title`, `artist`, `album`, `albumArtist`), `playlist.create` (`name`),
`playlist.createSmart` (`name`, supported `rule`), `playlist.rename`
(`playlistId`, `name`), and `playlist.add`/`playlist.remove`
(`playlistId`, `mediaId`). `playlist.addMany` and `playlist.removeMany` take a
`mediaIds` array. Deleting a media item requires the separate
`library.delete` grant and moves it to Yureru's trash. Deleting a playlist
requires `playlist.manage`. Smart playlists are read-only to extension actions.
The app validates IDs, bounds text and batch sizes, and rejects commands
without the matching grant.

The permission IDs currently defined are `library.read`, `library.write`,
`library.delete`, `playlist.manage`, `player.control`, `ui.contribute`,
`pip.control`, `theme.customize`, and `extension.storage`.
An extension can offer named palettes with `themes: [{ id, name, accent,
darkBackground, lightBackground }]`; colors use `#RRGGBB` or `#AARRGGBB`.
Optional `darkSurface`, `lightSurface`, `darkText`, `lightText`, `cornerRadius`
and `fontScale` customize the app-wide Material theme as well. Radius is capped
at 48 logical pixels and text scaling at 0.75–1.5. Extension pages can supply
their own screens and controls, while the host keeps navigation, playback and
other core behavior intact.
Permissions are granted separately and
can be revoked in Settings → App → Extensions. Extensions can transform import
metadata, contribute their own extension page/actions/themes, and call the
documented playback, queue, and library commands. New app capabilities can be
added to this host API without granting extensions direct access to app state
or the device.

For security, do not install packages from sources you do not trust. A
JavaScript sandbox limits access but is not a substitute for reviewing code.
