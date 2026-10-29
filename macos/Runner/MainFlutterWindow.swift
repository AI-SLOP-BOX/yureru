import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers
import AVFoundation

class MainFlutterWindow: NSWindow {
  private var mediaPickerChannel: FlutterMethodChannel?
  private var defaultMediaPlayerChannel: FlutterMethodChannel?
  private var appExitChannel: FlutterMethodChannel?
  private var nativeMenuChannel: FlutterMethodChannel?
  private var systemMediaControls: SystemMediaControls?
  private var normalWindowFrameBeforeCompactPlayer: NSRect?
  private var normalWindowMinSizeBeforeCompactPlayer: NSSize?
  private var normalWindowAspectRatioBeforeCompactPlayer: NSSize?
  private var normalWindowLevelBeforeCompactPlayer: NSWindow.Level?
  private var normalWindowStyleMaskBeforeCompactPlayer: NSWindow.StyleMask?
  private var normalWindowMovableByBackgroundBeforeCompactPlayer: Bool?
  private var normalWindowPreservesContentDuringLiveResizeBeforeCompactPlayer: Bool?

  // Fullscreen player mode still needs to receive keyboard shortcuts.
  override var canBecomeKey: Bool { true }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Default window size so the 3-pane layout (AppShell switches at >=1000pt)
    // is shown out of the box; falls back to the screen when it is smaller.
    let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    var windowFrame = self.frame
    windowFrame.size = NSSize(
      width: min(1280, visible.width - 40),
      height: min(820, visible.height - 60))
    self.contentViewController = flutterViewController
    nativeMenuChannel = FlutterMethodChannel(
      name: "yureru/native_menu",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    // Let the desktop window shrink to a phone-sized viewport so the narrow
    // Flutter layout can be tested and used without a desktop-width minimum.
    self.minSize = NSSize(width: 360, height: 600)
    self.setFrame(windowFrame, display: true)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    registerMediaPicker(flutterViewController)
    registerDefaultMediaPlayer(flutterViewController)
    registerAppExit(flutterViewController)
    systemMediaControls = SystemMediaControls(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
    makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)

    // Flutter engine startup can shrink the window once during initialization;
    // re-assert the desktop-layout size after that settles.
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
      guard let self = self, self.level != .floating, self.frame.size.width < 1000 else { return }
      self.setFrame(windowFrame, display: true)
      self.center()
    }
  }

  private func registerAppExit(_ flutterViewController: FlutterViewController) {
    appExitChannel = FlutterMethodChannel(
      name: "yureru/app_exit",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
  }

  private func registerDefaultMediaPlayer(_ flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "yureru/default_media_player",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    defaultMediaPlayerChannel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "setAsDefaultMediaPlayer" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard #available(macOS 14.0, *) else {
        result(FlutterError(
          code: "unsupported_os",
          message: "Setting default media apps requires macOS 14 or later.",
          details: nil))
        return
      }

      Task { @MainActor in
        do {
          let appURL = Bundle.main.bundleURL
          try await NSWorkspace.shared.setDefaultApplication(
            at: appURL,
            toOpen: UTType.movie)
          try await NSWorkspace.shared.setDefaultApplication(
            at: appURL,
            toOpen: UTType.audio)
          result(nil)
        } catch {
          result(FlutterError(
            code: "default_app_rejected",
            message: error.localizedDescription,
            details: nil))
        }
      }
    }
  }

  func openSettingsFromMenu() {
    nativeMenuChannel?.invokeMethod("openSettings", arguments: nil)
    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(nil)
  }

  func prepareForTermination(completion: @escaping () -> Void) {
    guard let appExitChannel else {
      completion()
      return
    }
    appExitChannel.invokeMethod("prepareForTermination", arguments: nil) { [weak self] _ in
      self?.systemMediaControls?.clear()
      completion()
    }
  }

  /// macOS file picker: native NSOpenPanel shown as a sheet of this window.
  /// file_picker's `runModal()` blocks the (merged) platform+UI thread and the
  /// panel can stay hidden behind the window when the app is not active, so we
  /// present it ourselves: non-blocking + sheet + explicit app activation.
  private func registerMediaPicker(_ flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "yureru/media_picker",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "pickVideos":
        self?.pickVideos(result: result)
      case "pickFolder":
        self?.pickFolder(result: result)
      case "toggleFullscreen":
        DispatchQueue.main.async {
          (NSApp.keyWindow as? MainFlutterWindow ?? self)?.toggleFullScreen(nil)
          result(nil)
        }
      case "setCompactPlayerWindow":
        let applyCompactFrame = { [weak self] in
          // Flutter can have a key window that differs from the window that
          // registered this channel (for example after a PiP surface swap).
          // Always resize the visible app window, while keeping the receiver
          // as a fallback for startup and headless states.
          let target = (NSApp.keyWindow as? MainFlutterWindow) ?? self
          guard let target else {
            result(FlutterError(
              code: "window_unavailable",
              message: "Yureru window is unavailable",
              details: nil))
            return
          }
          target.setCompactPlayerWindow()
          result(["width": target.frame.width, "height": target.frame.height])
        }
        if Thread.isMainThread {
          applyCompactFrame()
        } else {
          DispatchQueue.main.async(execute: applyCompactFrame)
        }
      case "restoreCompactPlayerWindow":
        DispatchQueue.main.async { [weak self] in
          self?.restoreCompactPlayerWindow()
          result(nil)
        }
      case "makeThumbnail":
        self?.makeThumbnail(call: call, result: result)
      case "probeDuration":
        self?.probeDuration(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    mediaPickerChannel = channel
  }

  /// Let AppKit manage the fullscreen transition. Resizing the Flutter window
  /// directly with setFrame(screen.frame) can crash Flutter's macOS resize
  /// synchronizer, and native fullscreen supplies the expected auto-hiding
  /// red/yellow/green controls.
  @objc override func toggleFullScreen(_ sender: Any?) {
    // PiP uses its own saved window state and cannot be nested with cinema mode.
    guard normalWindowFrameBeforeCompactPlayer == nil else { return }
    super.toggleFullScreen(sender)
  }

  private func setCompactPlayerWindow() {
    guard normalWindowFrameBeforeCompactPlayer == nil else { return }
    normalWindowFrameBeforeCompactPlayer = frame
    normalWindowMinSizeBeforeCompactPlayer = minSize
    normalWindowAspectRatioBeforeCompactPlayer = contentAspectRatio
    normalWindowLevelBeforeCompactPlayer = level
    normalWindowStyleMaskBeforeCompactPlayer = styleMask
    normalWindowMovableByBackgroundBeforeCompactPlayer = isMovableByWindowBackground
    normalWindowPreservesContentDuringLiveResizeBeforeCompactPlayer = preservesContentDuringLiveResize

    styleMask = [.borderless, .resizable]
    isMovableByWindowBackground = true
    minSize = NSSize(width: 220, height: 124)
    contentAspectRatio = NSSize(width: 16, height: 9)
    level = .floating
    // Flutter redraws and recomposites its full surface for every live-resize
    // event. Reuse the current frame while dragging and let it redraw once the
    // resize ends, which keeps interactive PiP resizing responsive.
    preservesContentDuringLiveResize = true

    // Keep the regular app's minimum size intact, while the compact player
    // uses a real 16:9 content area small enough for PiP.
    let contentRect = NSRect(x: 0, y: 0, width: 240, height: 135)
    let compactFrameSize = frameRect(forContentRect: contentRect).size
    var compactFrame = frame
    compactFrame.origin.y += compactFrame.height - compactFrameSize.height
    compactFrame.size = compactFrameSize
    setFrame(compactFrame, display: true, animate: false)
  }

  private func restoreCompactPlayerWindow() {
    guard let originalFrame = normalWindowFrameBeforeCompactPlayer else { return }
    styleMask = normalWindowStyleMaskBeforeCompactPlayer ?? [.titled, .closable, .miniaturizable, .resizable]
    isMovableByWindowBackground = normalWindowMovableByBackgroundBeforeCompactPlayer ?? false
    preservesContentDuringLiveResize = normalWindowPreservesContentDuringLiveResizeBeforeCompactPlayer ?? false
    level = normalWindowLevelBeforeCompactPlayer ?? .normal
    minSize = normalWindowMinSizeBeforeCompactPlayer ?? NSSize(width: 360, height: 600)
    contentAspectRatio = normalWindowAspectRatioBeforeCompactPlayer ?? .zero
    // The Dart window-manager path also restores bounds after this channel
    // call. Avoid AppKit's asynchronous frame animation here: overlapping
    // NSWindow frame animations can throw from _reallySetFrame on macOS.
    setFrame(originalFrame, display: true, animate: false)
    normalWindowFrameBeforeCompactPlayer = nil
    normalWindowMinSizeBeforeCompactPlayer = nil
    normalWindowAspectRatioBeforeCompactPlayer = nil
    normalWindowLevelBeforeCompactPlayer = nil
    normalWindowStyleMaskBeforeCompactPlayer = nil
    normalWindowMovableByBackgroundBeforeCompactPlayer = nil
    normalWindowPreservesContentDuringLiveResizeBeforeCompactPlayer = nil
  }

  private func pickVideos(result: @escaping FlutterResult) {
    let present = {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = true
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      panel.showsHiddenFiles = false
      panel.treatsFilePackagesAsDirectories = false
      panel.message = "インポートする音声・動画ファイルを選択してください"
      panel.prompt = "インポート"
      var types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .mpeg2Video]
      types.append(.audio)
      if #available(macOS 11.0, *) {
        for ext in ["mkv", "webm", "flv", "wmv", "ts", "m2ts", "3gp", "m4v", "mp3", "opus", "ogg", "oga", "m4a", "aac", "wav", "flac", "aiff", "aif", "alac", "caf"] {
          if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        panel.allowedContentTypes = types
      } else {
        panel.allowedFileTypes = ["mp4", "m4v", "mov", "mkv", "webm", "avi", "ts",
          "m2ts", "mpg", "mpeg", "flv", "wmv", "3gp", "mp3", "opus", "ogg", "m4a", "aac", "wav", "flac", "aiff"]
      }
      let finish: (NSApplication.ModalResponse) -> Void = { response in
        if response == .OK, !panel.urls.isEmpty {
          result(panel.urls.map { $0.path })
        } else {
          result(nil)
        }
      }
      NSApp.activate(ignoringOtherApps: true)
      panel.beginSheetModal(for: self, completionHandler: finish)
    }
    if Thread.isMainThread {
      present()
    } else {
      DispatchQueue.main.async(execute: present)
    }
  }

  /// Folder flow: pick a directory (Dart side scans it for video files).
  private func pickFolder(result: @escaping FlutterResult) {
    let present = {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.canCreateDirectories = false
      panel.showsHiddenFiles = false
      panel.message = "動画が入ったフォルダを選択してください（中の動画をまとめて取り込みます）"
      panel.prompt = "インポート"
      NSApp.activate(ignoringOtherApps: true)
      panel.beginSheetModal(for: self) { response in
        if response == .OK, let url = panel.url {
          result(url.path)
        } else {
          result(nil)
        }
      }
    }
    if Thread.isMainThread {
      present()
    } else {
      DispatchQueue.main.async(execute: present)
    }
  }

  /// Video thumbnail: best-of-N JPEG frame via AVFoundation (runs off-main).  /// Near-black / near-white frames are skipped so every thumb shows
  /// something meaningful. Dart caches the bytes per media id.
  private func makeThumbnail(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      result(FlutterError(code: "BAD_ARGS", message: "path required", details: nil))
      return
    }
    let maxWidth = (args["maxWidth"] as? NSNumber)?.intValue ?? 320
    DispatchQueue.global(qos: .utility).async {
      do {
        let (data, ms) = try bestThumbnail(path: path, maxWidth: maxWidth)
        result(["jpg": FlutterStandardTypedData(bytes: data), "timeMs": ms])
      } catch let e as NSError {
        result(FlutterError(code: "THUMB_FAIL", message: e.localizedDescription, details: nil))
      } catch {
        result(FlutterError(code: "THUMB_FAIL", message: "\(error)", details: nil))
      }
    }
  }

  /// Duration probe: metadata only, no decode. Returns milliseconds.
  private func probeDuration(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      result(FlutterError(code: "BAD_ARGS", message: "path required", details: nil))
      return
    }
    DispatchQueue.global(qos: .utility).async {
      let asset = AVAsset(url: URL(fileURLWithPath: path))
      guard asset.tracks(withMediaType: .video).first != nil else {
        result(FlutterError(code: "NO_VIDEO", message: "no video track", details: nil))
        return
      }
      let sec = CMTimeGetSeconds(asset.duration)
      guard sec.isFinite && sec > 0 else {
        result(FlutterError(code: "NO_DURATION", message: "unknown duration", details: nil))
        return
      }
      result(Int(sec * 1000))
    }
  }
}

/// Frame sampling fractions across the duration (avoid very head/tail:
/// fades, title cards and end screens live there). Dense enough that a
/// mostly-dark video still yields a bright textured candidate.
private let thumbFractions = [0.08, 0.16, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85]

/// Grab candidates, skip blank ones, return the best textured-bright frame
/// with its timestamp (ms). Score = variance x brightness weight, so dark
/// scenes with bright text lose to genuinely bright scenes.
/// Falls back to the brightest candidate when everything is dark.
private func bestThumbnail(path: String, maxWidth: Int) throws -> (Data, Int) {
  let asset = AVAsset(url: URL(fileURLWithPath: path))
  guard asset.tracks(withMediaType: .video).first != nil else {
    throw NSError(domain: "yureru", code: -1,
      userInfo: [NSLocalizedDescriptionKey: "no video track: \(path)"])
  }
  let durSec = CMTimeGetSeconds(asset.duration)
  guard durSec.isFinite && durSec > 1.0 else {
    // Very short/unknown: single grab near the middle.
    let ms = Int(min(1000.0, max(300.0, durSec * 500.0)))
    let (cg, _) = try frameGrab(asset: asset,
      sec: Double(ms) / 1000.0, maxWidth: maxWidth)
    return (try jpegEncode(cg), ms)
  }
  let gen = thumbnailGenerator(asset: asset, maxWidth: maxWidth)
  var fallback: (image: CGImage, avg: Double, ms: Int)?
  var best: (image: CGImage, score: Double, ms: Int)?
  for (_, f) in thumbFractions.enumerated() {
    let sec = min(durSec * f, durSec - 0.2)
    guard let (cg, stats) = try? frameGrab(asset: asset, sec: sec, maxWidth: maxWidth, generator: gen) else { continue }
    let ms = Int(sec * 1000)
    if fallback == nil || stats.avg > fallback!.avg {
      fallback = (cg, stats.avg, ms)
    }
    // Blank or pitch black / blown out white frames look broken in the UI; skip them when possible.
    if stats.avg < 0.04 || stats.avg > 0.96 { continue }
    let weight = max(0.0, min(1.0, (stats.avg - 0.04) / 0.92))
    let score = (stats.variance + 0.001) * weight
    if best == nil || score > best!.score {
      best = (cg, score, ms)
    }
  }
  if let b = best { return (try jpegEncode(b.image), b.ms) }
  if let fb = fallback {
    return (try jpegEncode(fb.image), fb.ms)
  }
  throw NSError(domain: "yureru", code: -3,
    userInfo: [NSLocalizedDescriptionKey: "no decodable frame: \(path)"])
}

private func thumbnailGenerator(asset: AVAsset, maxWidth: Int) -> AVAssetImageGenerator {
  let gen = AVAssetImageGenerator(asset: asset)
  gen.appliesPreferredTrackTransform = true
  gen.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(0.5, preferredTimescale: 600)
  gen.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(0.5, preferredTimescale: 600)
  let w = max(64, maxWidth)
  gen.maximumSize = CGSize(width: w, height: w * 2)
  return gen
}

/// Grab one frame plus its luminance stats (no encoding yet).
private func frameGrab(asset: AVAsset, sec: Double, maxWidth: Int,
    generator gen: AVAssetImageGenerator? = nil) throws -> (CGImage, (avg: Double, variance: Double)) {
  let g = gen ?? thumbnailGenerator(asset: asset, maxWidth: maxWidth)
  var actual = CMTime.zero
  let cg = try g.copyCGImage(
    at: CMTimeMakeWithSeconds(max(0, sec), preferredTimescale: 600), actualTime: &actual)
  return (cg, lumaStats(cg))
}

/// JPEG-encode one frame (only the winner pays this cost).
private func jpegEncode(_ cg: CGImage) throws -> Data {
  let img = NSImage(cgImage: cg, size: .zero)
  guard let tiff = img.tiffRepresentation,
        let bmp = NSBitmapImageRep(data: tiff),
        let jpeg = bmp.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
    throw NSError(domain: "yureru", code: -2,
      userInfo: [NSLocalizedDescriptionKey: "jpeg encode failed"])
  }
  return jpeg
}

/// Mean + variance of luminance over a 48px sampling grid.
private func lumaStats(_ cg: CGImage) -> (avg: Double, variance: Double) {
  let w = 48, h = 48
  guard let ctx = CGContext(data: nil, width: w, height: h,
      bitsPerComponent: 8, bytesPerRow: w * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
    let buf = ctx.data else { return (0.5, 0) }
  ctx.interpolationQuality = .low
  ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
  let px = buf.bindMemory(to: UInt8.self, capacity: w * h * 4)
  var mean = 0.0
  var m2 = 0.0
  var n = 0.0
  for i in 0 ..< w * h {
    let r = Double(px[i * 4]) / 255.0
    let g = Double(px[i * 4 + 1]) / 255.0
    let b = Double(px[i * 4 + 2]) / 255.0
    let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    n += 1
    let d = lum - mean
    mean += d / n
    m2 += d * (lum - mean)
  }
  guard n > 0 else { return (0.5, 0) }
  return (mean, m2 / n)
}
