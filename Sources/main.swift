import Cocoa

// NSApplication enters on the process main thread; express that invariant to
// Swift concurrency so every AppKit lifecycle callback starts on MainActor.
MainActor.assumeIsolated {
  let app = NSApplication.shared
  let delegate = AppDelegate()
  app.delegate = delegate
  app.setActivationPolicy(.regular)
  app.run()
}
