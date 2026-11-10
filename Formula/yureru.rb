class Yureru < Formula
  desc "Local video and music player"
  homepage "https://github.com/AI-SLOP-BOX/yureru"
  url "https://github.com/AI-SLOP-BOX/yureru/releases/download/v1.0.6/yureru-linux-x64.tar.gz"
  version "1.0.6"
  sha256 "037999614fd66a15c96a4800f723784f944e4b013b5bbe267964b1228215dcd7"
  license "MIT"

  depends_on :linux
  depends_on "gtk+3"
  depends_on "json-glib"
  depends_on "mpv"

  def install
    odie "Yureru's Linux build currently supports x86_64 only" unless Hardware::CPU.intel?

    libexec.install Dir["*"]

    (bin / "yureru").write <<~SH
      #!/bin/sh
      brew_prefix="$(brew --prefix)"
      export LD_LIBRARY_PATH="${brew_prefix}/lib:${brew_prefix}/opt/gtk+3/lib:${brew_prefix}/opt/json-glib/lib:${brew_prefix}/opt/mpv/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
      exec "#{libexec}/Yureru" "$@"
    SH
    chmod 0755, (bin / "yureru")

    icon = libexec / "data/flutter_assets/assets/yureru_logo.png"
    odie "The release bundle is missing the Yureru icon" unless icon.file?
    (share / "icons/hicolor/512x512/apps").install icon => "dev.yureru.yureru.png"
    (share / "applications/dev.yureru.yureru.desktop").write <<~DESKTOP
      [Desktop Entry]
      Type=Application
      Name=Yureru
      Comment=Local video and music player
      Exec=#{bin}/yureru
      Icon=dev.yureru.yureru
      Terminal=false
      Categories=AudioVideo;Player;
      StartupWMClass=dev.yureru.yureru
    DESKTOP
  end

  def caveats
    <<~EOS
      This Linux package is x86_64-only. To install the newest release, use the
      yureru.rb formula attached to that GitHub release.
    EOS
  end
end
