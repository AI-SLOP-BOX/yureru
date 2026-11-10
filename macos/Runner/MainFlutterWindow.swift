import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers
import AVFoundation
import AVKit
import WebKit

class MainFlutterWindow: NSWindow {
  private var mediaPickerChannel: FlutterMethodChannel?
  private var defaultMediaPlayerChannel: FlutterMethodChannel?
  private var appExitChannel: FlutterMethodChannel?
  private var nativeMenuChannel: FlutterMethodChannel?
  private var systemMediaControls: SystemMediaControls?
  private var nativePictureInPicture: NativeSystemPictureInPicture?

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
          // Setting only public.movie/public.audio does not override a user's
          // more specific choice (for example public.mpeg-4 -> IINA). Register
          // every stable media UTI supported by the importer, then verify the
          // resulting Launch Services handlers before reporting success.
          let extensions = [
            "mp4", "m4v", "mov", "mkv", "webm", "avi", "ts", "m2ts",
            "mpg", "mpeg", "flv", "wmv", "3gp", "3g2", "ogv", "vob",
            "divx", "mp3", "opus", "ogg", "oga", "m4a", "aac", "wav",
            "flac", "aiff", "alac", "caf",
          ]
          var types: [UTType] = [.movie, .video, .audio]
          for fileExtension in extensions {
            if let type = UTType(filenameExtension: fileExtension),
               !type.identifier.hasPrefix("dyn.") {
              types.append(type)
            }
          }
          var uniqueTypes: [UTType] = []
          var seen = Set<String>()
          for type in types where seen.insert(type.identifier).inserted {
            uniqueTypes.append(type)
          }
          for type in uniqueTypes {
            try await NSWorkspace.shared.setDefaultApplication(
              at: appURL,
              toOpen: type)
          }
          try await Task.sleep(nanoseconds: 350_000_000)
          let unresolved = uniqueTypes.filter { type in
            guard let handler = NSWorkspace.shared.urlForApplication(toOpen: type)
            else { return true }
            return handler.standardizedFileURL != appURL.standardizedFileURL
          }
          guard unresolved.isEmpty else {
            let names = unresolved.map(\.identifier).joined(separator: ", ")
            throw NSError(
              domain: "YureruDefaultMediaPlayer",
              code: 1,
              userInfo: [NSLocalizedDescriptionKey:
                "macOS did not assign Yureru to: \(names)"])
          }
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

  func openSearchFromMenu() {
    nativeMenuChannel?.invokeMethod("openSearch", arguments: nil)
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
    nativePictureInPicture = NativeSystemPictureInPicture(
      messenger: flutterViewController.engine.binaryMessenger,
      window: self)
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
    super.toggleFullScreen(sender)
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

/// macOS's OS-owned PiP uses AVPlayerLayer. Unsupported source formats are
/// prepared as temporary compatible media before they reach this controller.
private final class NativeSystemPictureInPicture: NSObject, AVPictureInPictureControllerDelegate, WKNavigationDelegate, WKScriptMessageHandler {
  private let channel: FlutterMethodChannel
  private let stateChannel: FlutterMethodChannel
  private weak var window: NSWindow?
  private var player: AVPlayer?
  private var playerLayer: AVPlayerLayer?
  private var pipController: AVPictureInPictureController?
  private var readinessObserver: NSKeyValueObservation?
  private var playbackObserver: NSKeyValueObservation?
  private var pendingStartResult: FlutterResult?
  private var pendingStartRate: Float = 1
  private var didPrimeInitialFrame = false
  private var lastStartFailure = "PiP start did not complete."
  private var positionTimer: Timer?
  private var initialSeekStarted = false
  private var webKitPlayer: WKWebView?
  private var webKitStartResult: FlutterResult?
  private var webKitStartTimeout: DispatchWorkItem?
  private var webKitUpdateResult: FlutterResult?
  private var webKitUpdateTimeout: DispatchWorkItem?
  private var webKitPositionTimer: Timer?
  private var endObserver: NSObjectProtocol?

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    channel = FlutterMethodChannel(name: "yureru/native_pip", binaryMessenger: messenger)
    stateChannel = FlutterMethodChannel(name: "yureru/media_picker", binaryMessenger: messenger)
    self.window = window
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "start":
        self.start(call.arguments as? [String: Any] ?? [:], result: result)
      case "lastStartFailure":
        result(self.lastStartFailure)
      case "startWebKit":
        self.startWebKit(call.arguments as? [String: Any] ?? [:], result: result)
      case "setPlaying":
        let shouldPlay = (call.arguments as? Bool) ?? false
        if self.webKitPlayer != nil {
          self.evaluateWebKit(shouldPlay ? "video.play()" : "video.pause()")
        } else if shouldPlay { self.player?.play() } else { self.player?.pause() }
        result(nil)
      case "setRate":
        let arguments = call.arguments as? [String: Any] ?? [:]
        let rate = (arguments["rate"] as? NSNumber)?.floatValue ?? 1
        if self.webKitPlayer != nil {
          self.evaluateWebKit("video.playbackRate = \(max(0.25, min(4, rate)))")
          if (arguments["playing"] as? Bool) != true { self.evaluateWebKit("video.pause()") }
        } else {
          self.player?.rate = (arguments["playing"] as? Bool) == true ? rate : 0
        }
        result(nil)
      case "seekTo":
        let seconds = (call.arguments as? NSNumber)?.doubleValue ?? 0
        if self.webKitPlayer != nil {
          self.evaluateWebKit("video.currentTime = \(max(0, seconds))")
        } else {
          self.player?.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
        }
        result(nil)
      case "updatePosition":
        // WebKit owns the PiP timeline while active; the Flutter-side player
        // remains paused and is synchronized when PiP closes.
        result(nil)
      case "update":
        let arguments = call.arguments as? [String: Any] ?? [:]
        if self.webKitPlayer != nil {
          self.updateWebKit(arguments, result: result)
        } else {
          self.update(arguments, result: result)
        }
      case "stop":
        if self.webKitPlayer != nil {
          self.evaluateWebKit("video.webkitSetPresentationMode('inline')")
        } else {
          self.pipController?.stopPictureInPicture()
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Use WebKit's native media stack for WebM on modern macOS. The bundled
  /// FFmpeg Kit can encode H.264 with VideoToolbox, but its AV1 decoder is
  /// software-only, making a full-length 4K WebM conversion take minutes.
  private func startWebKit(_ arguments: [String: Any], result: @escaping FlutterResult) {
    guard let rawUri = arguments["uri"] as? String,
          let window,
          let hostView = window.contentViewController?.view else {
      result(false)
      return
    }
    let url: URL
    if rawUri.hasPrefix("file://"), let fileURL = URL(string: rawUri) {
      url = fileURL
    } else if rawUri.hasPrefix("/") {
      url = URL(fileURLWithPath: rawUri)
    } else {
      result(false)
      return
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
      result(false)
      return
    }

    stopWebKitPlayer(notify: false)
    let config = WKWebViewConfiguration()
    config.mediaTypesRequiringUserActionForPlayback = []
    let controller = WKUserContentController()
    controller.add(self, name: "yureruPip")
    config.userContentController = controller
    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 180), configuration: config)
    webView.navigationDelegate = self
    webView.setValue(false, forKey: "drawsBackground")
    webView.alphaValue = 0.01
    hostView.addSubview(webView, positioned: .below, relativeTo: nil)
    webKitPlayer = webView
    webKitStartResult = result

    let position = max(0, (arguments["position"] as? NSNumber)?.doubleValue ?? 0)
    let rate = max(0.25, min(4, (arguments["rate"] as? NSNumber)?.doubleValue ?? 1))
    let playing = (arguments["playing"] as? Bool) ?? false
    let source = url.absoluteString
    let html = """
    <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
    <video id="v" playsinline webkit-playsinline preload="auto" src="\(source)" style="width:320px;height:180px;object-fit:contain"></video>
    <script>
    const video = document.getElementById('v');
    const bridge = (event) => window.webkit.messageHandlers.yureruPip.postMessage({
      event, position: Number.isFinite(video.currentTime) ? video.currentTime : 0,
      duration: Number.isFinite(video.duration) ? video.duration : 0,
      playing: !video.paused && !video.ended
    });
    video.addEventListener('webkitpresentationmodechanged', () => {
      bridge(video.webkitPresentationMode === 'picture-in-picture' ? 'started' : 'stopped');
    });
    video.addEventListener('ended', () => bridge('completed'));
    video.addEventListener('loadedmetadata', async () => {
      try {
        video.playbackRate = \(rate);
        if (Math.abs(video.currentTime - \(position)) > 0.05) {
          await new Promise(resolve => {
            video.addEventListener('seeked', resolve, { once: true });
            video.currentTime = \(position);
          });
        }
        if (video.readyState < 2) {
          await new Promise(resolve => video.addEventListener('loadeddata', resolve, { once: true }));
        }
        // WebKit needs a decoded media frame even when the requested PiP
        // state is paused. Warm the first frame, then restore the requested
        // state before asking macOS to present it.
        await video.play();
        if (!\(playing)) video.pause();
        if (typeof video.webkitSetPresentationMode === 'function') {
          video.webkitSetPresentationMode('picture-in-picture');
        } else if (typeof video.requestPictureInPicture === 'function') {
          await video.requestPictureInPicture();
        } else {
          bridge('pipUnsupported');
        }
      } catch (error) {
        bridge('pipFailed:' + (error && error.name ? error.name : 'unknown'));
      }
    }, { once: true });
    video.addEventListener('error', () => {
      const mediaError = video.error;
      bridge('error:' + (mediaError ? (mediaError.code + ':' + mediaError.message) : 'unknown'));
    });
    </script>
    """
    webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())

    let timeout = DispatchWorkItem { [weak self] in
      guard let self, self.webKitStartResult != nil else { return }
      self.finishWebKitStart(false)
    }
    webKitStartTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
    webKitPositionTimer?.invalidate()
    webKitPositionTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
      self?.evaluateWebKit("({position: video.currentTime || 0, duration: video.duration || 0, playing: !video.paused && !video.ended})", reportPosition: true)
    }
  }

  private func evaluateWebKit(_ expression: String, reportPosition: Bool = false) {
    webKitPlayer?.evaluateJavaScript("(() => { const video = document.getElementById('v'); if (!video) return null; return \(expression); })()") { [weak self] value, _ in
      guard reportPosition, let state = value as? [String: Any] else { return }
      self?.channel.invokeMethod("positionUpdated", arguments: state)
    }
  }

  private func updateWebKit(_ arguments: [String: Any], result: @escaping FlutterResult) {
    guard let rawUri = arguments["uri"] as? String else { result(false); return }
    let url = rawUri.hasPrefix("file://") ? URL(string: rawUri) : URL(fileURLWithPath: rawUri)
    guard let url, FileManager.default.fileExists(atPath: url.path) else { result(false); return }
    let source = url.absoluteString
    let sourceJSON = (try? String(data: JSONSerialization.data(withJSONObject: source), encoding: .utf8)) ?? "\"\(source)\""
    let position = max(0, (arguments["position"] as? NSNumber)?.doubleValue ?? 0)
    let rate = max(0.25, min(4, (arguments["rate"] as? NSNumber)?.doubleValue ?? 1))
    let playing = (arguments["playing"] as? Bool) ?? false
    webKitUpdateTimeout?.cancel()
    webKitUpdateResult?(false)
    webKitUpdateResult = result
    let timeout = DispatchWorkItem { [weak self] in
      self?.finishWebKitUpdate(false)
    }
    webKitUpdateTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)

    let script = """
    (() => {
      const video = document.getElementById('v');
      if (!video) return false;
      video.pause();
      video.addEventListener('loadedmetadata', async () => {
        try {
          video.playbackRate = \(rate);
          if (Math.abs(video.currentTime - \(position)) > 0.05) {
            await new Promise(resolve => {
              video.addEventListener('seeked', resolve, { once: true });
              video.currentTime = \(position);
            });
          }
          if (video.readyState < 2) {
            await new Promise(resolve => video.addEventListener('loadeddata', resolve, { once: true }));
          }
          if (\(playing)) await video.play();
          else video.pause();
          if (typeof video.webkitSetPresentationMode === 'function') {
            video.webkitSetPresentationMode('picture-in-picture');
          }
          window.webkit.messageHandlers.yureruPip.postMessage({ event: 'sourceUpdated' });
        } catch (_) {
          window.webkit.messageHandlers.yureruPip.postMessage({ event: 'sourceUpdateFailed' });
        }
      }, { once: true });
      video.addEventListener('error', () => {
        window.webkit.messageHandlers.yureruPip.postMessage({ event: 'sourceUpdateFailed' });
      }, { once: true });
      video.src = \(sourceJSON);
      video.load();
      return true;
    })()
    """
    webKitPlayer?.evaluateJavaScript(script) { [weak self] value, error in
      guard error != nil || (value as? Bool) != true else { return }
      self?.finishWebKitUpdate(false)
    }
  }

  private func finishWebKitUpdate(_ updated: Bool) {
    let result = webKitUpdateResult
    webKitUpdateResult = nil
    webKitUpdateTimeout?.cancel()
    webKitUpdateTimeout = nil
    if !updated, webKitPlayer != nil {
      stopWebKitPlayer(notify: true)
    }
    result?(updated)
  }

  private func finishWebKitStart(_ started: Bool) {
    let result = webKitStartResult
    webKitStartResult = nil
    webKitStartTimeout?.cancel()
    webKitStartTimeout = nil
    if !started { stopWebKitPlayer(notify: false) }
    result?(started)
  }

  private func stopWebKitPlayer(notify: Bool) {
    guard let webView = webKitPlayer else { return }
    let state: [String: Any] = ["position": 0, "duration": 0, "playing": false]
    let updateResult = webKitUpdateResult
    webKitUpdateResult = nil
    webKitUpdateTimeout?.cancel()
    webKitUpdateTimeout = nil
    webKitPositionTimer?.invalidate()
    webKitPositionTimer = nil
    webKitStartTimeout?.cancel()
    webKitStartTimeout = nil
    webKitStartResult = nil
    webView.configuration.userContentController.removeScriptMessageHandler(forName: "yureruPip")
    webView.navigationDelegate = nil
    webView.removeFromSuperview()
    webKitPlayer = nil
    updateResult?(false)
    if notify {
      channel.invokeMethod("stopped", arguments: state)
      stateChannel.invokeMethod("onSystemPictureInPictureChanged", arguments: false)
    }
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let payload = message.body as? [String: Any], let event = payload["event"] as? String else { return }
    switch event {
    case "started":
      finishWebKitStart(true)
      stateChannel.invokeMethod("onSystemPictureInPictureChanged", arguments: true)
      window?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    case "stopped":
      let state = payload.filter { $0.key != "event" }
      stopWebKitPlayer(notify: false)
      stateChannel.invokeMethod("onSystemPictureInPictureChanged", arguments: false)
      channel.invokeMethod("stopped", arguments: state)
    case let event where event.hasPrefix("error:"):
      NSLog("Yureru PiP: WebKit media error: %@", event)
      finishWebKitStart(false)
    case "completed":
      channel.invokeMethod("completed", arguments: nil)
    case "sourceUpdated":
      finishWebKitUpdate(true)
    case "sourceUpdateFailed":
      finishWebKitUpdate(false)
    case "pipUnsupported":
      NSLog("Yureru PiP: WebKit PiP request failed: %@", event)
    case let event where event.hasPrefix("pipFailed:"):
      NSLog("Yureru PiP: WebKit PiP request failed: %@", event)
    default:
      break
    }
  }

  private func start(_ arguments: [String: Any], result: @escaping FlutterResult) {
    lastStartFailure = "PiP is not supported or the player window is unavailable."
    guard AVPictureInPictureController.isPictureInPictureSupported(),
          let rawUri = arguments["uri"] as? String,
          let window,
          let hostView = window.contentViewController?.view else {
      result(false)
      return
    }
    hostView.wantsLayer = true
    guard let hostLayer = hostView.layer else { result(false); return }
    let url: URL
    if rawUri.hasPrefix("file://"), let fileURL = URL(string: rawUri) {
      url = fileURL
    } else if rawUri.hasPrefix("/") {
      url = URL(fileURLWithPath: rawUri)
    } else {
      // The macOS system player can't open app-managed/network URLs here.
      lastStartFailure = "The PiP player could not open this media URL."
      result(false)
      return
    }

    let item = AVPlayerItem(url: url)
    observeEndOfItem(item)
    let player = AVPlayer(playerItem: item)
    player.actionAtItemEnd = .pause
    let layer = AVPlayerLayer(player: player)
    layer.videoGravity = .resizeAspect
    if let sourceRect = arguments["sourceRect"] as? [String: NSNumber] {
      let left = CGFloat(sourceRect["left"]?.doubleValue ?? 0)
      let top = CGFloat(sourceRect["top"]?.doubleValue ?? 0)
      let width = CGFloat(sourceRect["width"]?.doubleValue ?? 0)
      let height = CGFloat(sourceRect["height"]?.doubleValue ?? 0)
      let bounds = hostLayer.bounds
      let frame = CGRect(
        x: left * bounds.width,
        y: bounds.height - (top + height) * bounds.height,
        width: width * bounds.width,
        height: height * bounds.height
      ).intersection(bounds)
      layer.frame = frame.isEmpty ? bounds : frame
    } else {
      layer.frame = hostLayer.bounds
    }
    layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    layer.opacity = 0.01
    hostLayer.addSublayer(layer)
    self.player = player
    playerLayer = layer
    initialSeekStarted = false
    didPrimeInitialFrame = false
    pendingStartRate = max(0.25, min(4, (arguments["rate"] as? NSNumber)?.floatValue ?? 1))
    let controller = AVPictureInPictureController(playerLayer: layer)
    guard let controller else {
      lastStartFailure = "macOS could not create a PiP controller for this video."
      layer.removeFromSuperlayer()
      self.player = nil
      playerLayer = nil
      result(false)
      return
    }
    controller.delegate = self
    pipController = controller
    playbackObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
      DispatchQueue.main.async {
        guard let self, self.pipController?.isPictureInPictureActive == true else { return }
        self.channel.invokeMethod("playbackStateChanged", arguments: player.timeControlStatus == .playing)
      }
    }
    pendingStartResult = result
    positionTimer?.invalidate()
    positionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.channel.invokeMethod("positionUpdated", arguments: self.currentPlaybackState())
    }
    readinessObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      DispatchQueue.main.async {
        guard let self else { return }
        if item.status == .failed {
          self.lastStartFailure = item.error?.localizedDescription ?? "AVPlayer could not load this video."
          NSLog("Yureru PiP: AVPlayerItem failed: %@", self.lastStartFailure)
          self.finishStart(false)
        } else if item.status == .readyToPlay, !self.initialSeekStarted {
          self.initialSeekStarted = true
          let position = max(0, (arguments["position"] as? NSNumber)?.doubleValue ?? 0)
          player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) { [weak self] _ in
            DispatchQueue.main.async {
              self?.tryStart(playing: (arguments["playing"] as? Bool) ?? false, deadline: CACurrentMediaTime() + 4)
            }
          }
        }
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
      guard let self, self.pendingStartResult != nil else { return }
      self.lastStartFailure = "Timed out waiting for macOS to start PiP."
      self.finishStart(false)
    }
  }

  private func tryStart(playing: Bool, deadline: CFTimeInterval) {
    guard let controller = pipController, let layer = playerLayer else {
      finishStart(false)
      return
    }
    // AVPlayerLayer only becomes ready after AVPlayer has decoded a frame.
    // Starting it after waiting for isReadyForDisplay deadlocks on some AV1
    // assets: the paused layer never produces the frame PiP is waiting for.
    if !didPrimeInitialFrame {
      didPrimeInitialFrame = true
      player?.playImmediately(atRate: pendingStartRate)
    }
    guard layer.isReadyForDisplay else {
      if CACurrentMediaTime() < deadline {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
          self?.tryStart(playing: playing, deadline: deadline)
        }
      } else {
        lastStartFailure = "AVPlayer did not decode a video frame in time."
        NSLog("Yureru PiP: %@", lastStartFailure)
        finishStart(false)
      }
      return
    }
    guard controller.isPictureInPicturePossible else {
      if CACurrentMediaTime() < deadline {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
          self?.tryStart(playing: playing, deadline: deadline)
        }
      } else {
        lastStartFailure = "macOS says PiP is not currently possible for this video."
        NSLog("Yureru PiP: %@", lastStartFailure)
        finishStart(false)
      }
      return
    }
    if playing {
      player?.playImmediately(atRate: pendingStartRate)
    } else {
      player?.pause()
    }
    controller.startPictureInPicture()
  }

  private func finishStart(_ started: Bool) {
    let result = pendingStartResult
    pendingStartResult = nil
    readinessObserver = nil
    if !started {
      playbackObserver = nil
      pipController?.delegate = nil
      pipController = nil
      player?.pause()
      player = nil
      playerLayer?.removeFromSuperlayer()
      playerLayer = nil
    }
    result?(started)
  }

  private func update(_ arguments: [String: Any], result: @escaping FlutterResult) {
    guard let uri = arguments["uri"] as? String else {
      result(false)
      return
    }
    let url: URL
    if uri.hasPrefix("file://"), let fileURL = URL(string: uri) {
      url = fileURL
    } else if uri.hasPrefix("/") {
      url = URL(fileURLWithPath: uri)
    } else {
      result(false)
      return
    }
    let item = AVPlayerItem(url: url)
    observeEndOfItem(item)
    player?.replaceCurrentItem(with: item)
    let position = (arguments["position"] as? NSNumber)?.doubleValue ?? 0
    let shouldPlay = (arguments["playing"] as? Bool) ?? false
    let rate = (arguments["rate"] as? NSNumber)?.floatValue ?? 1
    readinessObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      DispatchQueue.main.async {
        guard let self else { result(false); return }
        if item.status == .failed {
          NSLog("Yureru PiP: updated AVPlayerItem failed: %@", item.error?.localizedDescription ?? "unknown")
          self.readinessObserver = nil
          result(false)
          self.pipController?.stopPictureInPicture()
          return
        }
        guard item.status == .readyToPlay, let player = self.player else { return }
        self.readinessObserver = nil
        player.seek(to: CMTime(seconds: max(0, position), preferredTimescale: 600)) { [weak self] _ in
          DispatchQueue.main.async {
            guard self != nil else { result(false); return }
            if shouldPlay { player.playImmediately(atRate: rate) } else { player.pause() }
            result(true)
          }
        }
      }
    }
  }

  private func currentPlaybackState() -> [String: Any] {
    let time = CMTimeGetSeconds(player?.currentTime() ?? .zero)
    let duration = CMTimeGetSeconds(player?.currentItem?.duration ?? .zero)
    return [
      "position": time.isFinite ? max(0, time) : 0,
      "duration": duration.isFinite ? max(0, duration) : 0,
      "playing": player?.timeControlStatus == .playing,
    ]
  }

  private func observeEndOfItem(_ item: AVPlayerItem) {
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      self?.channel.invokeMethod("completed", arguments: nil)
    }
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    finishStart(true)
    stateChannel.invokeMethod("onSystemPictureInPictureChanged", arguments: true)
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
    lastStartFailure = error.localizedDescription
    NSLog("Yureru PiP: AVKit failed to start: %@", lastStartFailure)
    finishStart(false)
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    let state = currentPlaybackState()
    positionTimer?.invalidate()
    positionTimer = nil
    readinessObserver = nil
    if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
    playbackObserver = nil
    pipController?.delegate = nil
    pipController = nil
    player?.pause()
    player = nil
    playerLayer?.removeFromSuperlayer()
    playerLayer = nil
    stateChannel.invokeMethod("onSystemPictureInPictureChanged", arguments: false)
    channel.invokeMethod("stopped", arguments: state)
  }

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    completionHandler(true)
  }

  deinit {
    channel.setMethodCallHandler(nil)
    positionTimer?.invalidate()
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
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
