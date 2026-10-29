import Cocoa
import FlutterMacOS
import Darwin

@main
class AppDelegate: FlutterAppDelegate {
  override init() {
    // The bundled playback/video stack can receive SIGPIPE when a native
    // media pipe closes during startup. Treat it as a recoverable EPIPE so
    // macOS does not terminate the entire app before the window appears.
    Darwin.signal(SIGPIPE, SIG_IGN)
    super.init()
  }

  @IBAction func showPreferences(_ sender: Any?) {
    (mainFlutterWindow as? MainFlutterWindow)?.openSettingsFromMenu()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let window = sender.windows.compactMap({ $0 as? MainFlutterWindow }).first else {
      return .terminateNow
    }
    window.prepareForTermination {
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
