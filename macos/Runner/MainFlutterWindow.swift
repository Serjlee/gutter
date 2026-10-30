import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// "gutter/menu": app menu items handled on the Flutter side.
  private var menuChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    menuChannel = FlutterMethodChannel(
      name: "gutter/menu",
      binaryMessenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()

    // Once the menu bar is in place.
    DispatchQueue.main.async { self.setUpAppMenu() }
  }

  /// The app menu's items that Flutter handles: "Check for Updates…" under
  /// "About Gutter", and "Settings…" (⌘,), which the menu leaves unwired.
  private func setUpAppMenu() {
    guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }
    let updates = NSMenuItem(
      title: "Check for Updates…",
      action: #selector(checkForUpdates(_:)),
      keyEquivalent: "")
    updates.target = self
    appMenu.insertItem(updates, at: min(1, appMenu.items.count))

    var settings = appMenu.items.first { $0.keyEquivalent == "," }
    if settings == nil {
      let item = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ",")
      appMenu.insertItem(item, at: min(3, appMenu.items.count))
      settings = item
    }
    settings?.action = #selector(openSettings(_:))
    settings?.target = self
  }

  @objc private func checkForUpdates(_ sender: Any?) {
    menuChannel?.invokeMethod("checkForUpdates", arguments: nil)
  }

  @objc private func openSettings(_ sender: Any?) {
    menuChannel?.invokeMethod("openSettings", arguments: nil)
  }
}
