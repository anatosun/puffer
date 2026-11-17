import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // The smallest window that still fits the phone layout; AppKit keeps the frame across starts.
    self.contentMinSize = NSSize(width: 400, height: 560)
    self.setFrameAutosaveName("PufferMainWindow")

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
