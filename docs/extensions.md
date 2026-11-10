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

Extensions can also add small, declarative screens and actions inside Yureru.
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
  "hooks": ["library.write.mediaImport", "extension.action.clean"],
  "permissions": ["library.write", "ui.contribute"]
}
```

```js
Yureru.on("library.write.mediaImport", ({ items }) => items.map((media) => ({
  ...media,
  title: media.title.replace(/^曲：/, ""),
})));
```

The following registers an extension page and an action button. Action hooks
must be listed in the manifest, use the `extension.action.<id>` form, and the
user must grant `ui.contribute`. Pages support text, separators, buttons, text
inputs, toggles, and sliders. Values are passed to action handlers in
`context.form`. The host validates and limits every contribution before
displaying it.

```js
Yureru.register({
  commands: [
    { id: "clean", title: "Clean library titles", action: "clean", icon: "library" }
  ],
  pages: [{
    id: "about-tools",
    title: "Title tools",
    blocks: [
      { type: "text", text: "Run title cleanup tools from this page." },
      { type: "input", id: "prefix", label: "Leading text", value: "曲：" },
      { type: "toggle", id: "enabled", label: "Enable cleanup", value: true },
      { type: "slider", id: "strength", label: "Match strength", min: 0, max: 1, value: 0.8 },
      { type: "divider" },
      { type: "button", label: "Show status", action: "clean" }
    ]
  }]
});

Yureru.on("extension.action.clean", (context) => {
  // Return a short status string for the host to show to the user.
  return "Ready";
});
```

Place `manifest.json` and `main.js` at the package root. Optional files may be
placed under `assets/`. The app rejects other paths, symbolic links, packages
over 20 MB, expanded contents over 32 MB, and packages with more than 80 files.
JavaScript is limited to 500 ms, 16 MB of runtime memory, and a 256 KB stack.
The working example is in `examples/extensions/title-cleanup/`; zip those two
files into a `.yureru` file to install it.

An action hook may also read/write the extension's own small JSON storage when
the user grants `extension.storage`. The event then includes a `storage` object;
return `{ storage: updatedObject, result: "message" }` to persist it. Storage is
isolated by extension ID, limited to 64 KB, and cannot address arbitrary files.

Action results can ask Yureru to perform host operations. They are checked again
against the granted permission before execution:

```js
Yureru.on("extension.action.next", () => ({
  command: { type: "player.next" },
  message: "Skipped to the next item."
}));
```

`player.control` allows `player.toggle`, `player.next`, `player.previous`,
`player.seek` (`positionMs`), `queue.playNext` (`mediaId`), and `queue.append`
(`mediaId`). `library.write` allows `library.favorite` (`mediaId`),
`library.metadata` (`mediaId`, optional `title`/`artist`), and
`playlist.add`/`playlist.remove` (`playlistId`, `mediaId`). The app validates
IDs, bounds text, and rejects commands without the matching grant.

The permission IDs currently defined are `library.read`, `library.write`,
`player.control`, `ui.contribute`, `theme.customize`, and `extension.storage`.
An extension can offer named palettes with `themes: [{ id, name, accent,
darkBackground, lightBackground }]`; colors use `#RRGGBB` or `#AARRGGBB`.
Permissions are granted separately and
can be revoked in Settings → App → Extensions. Extensions can transform import
metadata, contribute their own extension page/actions/themes, and call the
documented playback, queue, and library commands. New app capabilities can be
added to this host API without granting extensions direct access to app state
or the device.

For security, do not install packages from sources you do not trust. A
JavaScript sandbox limits access but is not a substitute for reviewing code.
