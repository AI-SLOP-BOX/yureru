# Linux packages

Yureru's Linux build currently targets **x86_64**. The Linux FFmpeg Kit
integration does not yet provide an aarch64 build.

## Flatpak: Fedora, KDE, GNOME, and other desktops

The release workflow builds `yureru-linux-x86_64.flatpak` against the
Freedesktop runtime. Install it with:

```sh
flatpak install --user ./yureru-linux-x86_64.flatpak
```

The bundle points to Flathub for its runtime and FFmpeg extension. Flatpak's
file chooser portal grants access to other folders when selected; Videos,
Music, and Pictures are available read-only by default. Wayland, X11, audio,
and GPU rendering are enabled. KDE users need the KDE desktop portal installed
for the native file chooser; GNOME users use the GNOME portal.

The `.flatpak` bundle is a direct-download package, not an update repository.
Install a newer release bundle to update. A `.flatpakref` will be generated only
after Yureru has a hosted Flatpak repository and a repository signing key; a
ref without those would point nowhere or ask users to trust an unsigned source.
Once both exist, `tools/render_flatpakref.py` creates the install link from the
repository URL and its exported public key:

```sh
gpg --export "$FLATPAK_SIGNING_KEY_ID" > build/yureru-flatpak-public.gpg
python3 tools/render_flatpakref.py \
  --repo-url https://example.invalid/yureru/repo \
  --gpg-public-key build/yureru-flatpak-public.gpg \
  --output build/yureru.flatpakref
```

## Homebrew on Linux

The formula installs the current published x86_64 release and obtains GTK 3,
JSON-GLib, and mpv through Homebrew. Fedora users need Homebrew's documented
bootstrap tools before installing it. Install from the repository formula:

```sh
brew install --formula https://raw.githubusercontent.com/AI-SLOP-BOX/yureru/main/Formula/yureru.rb
```

For a later version, the release workflow attaches a version-pinned `yureru.rb`
formula alongside the Linux archive. It can be installed directly from that
release and includes the archive checksum:

```sh
brew install --formula https://github.com/AI-SLOP-BOX/yureru/releases/latest/download/yureru.rb
```

Homebrew is an optional path for people who already use it. Flatpak remains the
recommended Linux download because it supplies the same runtime across Fedora,
Ubuntu, and KDE/GNOME desktops.

## Building the Flatpak locally

After building the normal Flutter Linux bundle, copy it into
`packaging/flatpak/bundle`, install the Freedesktop 26.08 runtime and SDK plus
`flatpak-builder`, then run:

```sh
flatpak-builder --user --force-clean --disable-rofiles-fuse \
  --repo=build/flatpak/repo build/flatpak/app \
  packaging/flatpak/dev.yureru.yureru.yml
flatpak build-bundle \
  --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  build/flatpak/repo build/yureru-linux-x86_64.flatpak \
  dev.yureru.yureru stable
```
