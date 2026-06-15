import Cocoa

// Programmatic entry point for the native macOS app.
// Replaces the Flutter @NSApplicationMain / MainMenu.xib bootstrap.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
