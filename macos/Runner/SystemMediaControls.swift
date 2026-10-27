import Cocoa
import FlutterMacOS
import MediaPlayer

/// Publishes the existing player to macOS; it does not own an audio player.
final class SystemMediaControls {
  private let channel: FlutterMethodChannel
  private let center = MPRemoteCommandCenter.shared()
  private let infoCenter = MPNowPlayingInfoCenter.default()
  private var targets: [(MPRemoteCommand, Any)] = []
  private var active = false
  private var artworkPath: String?
  private var artwork: MPMediaItemArtwork?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "yureru/system_media", binaryMessenger: messenger)
    bind(center.playCommand, "play")
    bind(center.pauseCommand, "pause")
    bind(center.togglePlayPauseCommand, "toggle")
    bind(center.nextTrackCommand, "next")
    bind(center.previousTrackCommand, "previous")
    let seek = center.changePlaybackPositionCommand
    let token = seek.addTarget { [weak self] event in
      guard let self, self.active,
            let event = event as? MPChangePlaybackPositionCommandEvent,
            event.positionTime.isFinite, event.positionTime >= 0 else { return .commandFailed }
      self.send("seek", value: event.positionTime * 1000)
      return .success
    }
    targets.append((seek, token))
    clear()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "update":
        self.update(call.arguments as? [String: Any] ?? [:])
        result(nil)
      case "clear":
        self.clear()
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func bind(_ command: MPRemoteCommand, _ method: String) {
    let token = command.addTarget { [weak self] _ in
      guard let self, self.active else { return .noSuchContent }
      self.send(method)
      return .success
    }
    targets.append((command, token))
  }

  private func send(_ method: String, value: Any? = nil) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.active else { return }
      self.channel.invokeMethod(method, arguments: value)
    }
  }

  private func update(_ data: [String: Any]) {
    guard data["active"] as? Bool == true else { clear(); return }
    active = true
    let playing = data["playing"] as? Bool ?? false
    let rate = data["rate"] as? Double ?? 1
    let duration = max(0, (data["durationMs"] as? NSNumber)?.doubleValue ?? 0) / 1000
    let elapsed = max(0, (data["positionMs"] as? NSNumber)?.doubleValue ?? 0) / 1000
    let path = data["artworkPath"] as? String
    if path != artworkPath {
      artworkPath = path
      artwork = nil
      if let path, let image = NSImage(contentsOfFile: path) {
        artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      }
    }
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: data["title"] as? String ?? "Yureru",
      MPMediaItemPropertyArtist: data["artist"] as? String ?? "",
      MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: min(elapsed, duration > 0 ? duration : elapsed),
      MPNowPlayingInfoPropertyPlaybackRate: playing ? rate : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: rate,
      MPNowPlayingInfoPropertyExternalContentIdentifier: data["mediaId"] as? String ?? "",
    ]
    if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
    infoCenter.nowPlayingInfo = info
    infoCenter.playbackState = playing ? .playing : .paused
    center.playCommand.isEnabled = true
    center.pauseCommand.isEnabled = true
    center.togglePlayPauseCommand.isEnabled = true
    center.nextTrackCommand.isEnabled = data["canNext"] as? Bool ?? false
    center.previousTrackCommand.isEnabled = data["canPrevious"] as? Bool ?? false
    center.changePlaybackPositionCommand.isEnabled = duration > 0
  }

  func clear() {
    active = false
    artworkPath = nil
    artwork = nil
    for (command, _) in targets { command.isEnabled = false }
    infoCenter.playbackState = .stopped
    infoCenter.nowPlayingInfo = nil
  }

  deinit {
    channel.setMethodCallHandler(nil)
    for (command, token) in targets { command.removeTarget(token) }
    clear()
  }
}
