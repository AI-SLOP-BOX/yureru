import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
       let iconImage = NSImage(contentsOfFile: iconPath) {
      NSApplication.shared.applicationIconImage = iconImage
    }
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
