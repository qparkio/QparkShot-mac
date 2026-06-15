import Cocoa
import Carbon
import SwiftUI
import ScreenCaptureKit

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  static var shared: AppDelegate { NSApp.delegate as! AppDelegate }
  
  private static let hotKeySignature = OSType(0x51504B53) // "QPKS"
  private static var hasRequestedScreenCapturePermissionInSession = false
  
  private struct RegisteredGlobalShortcut {
    let id: String
    let carbonID: UInt32
    let ref: EventHotKeyRef
  }
  
  var statusItem: NSStatusItem?
  var galleryWindow: NSWindow?
  
  private var hotkeyEventHandler: EventHandlerRef?
  private var registeredGlobalShortcuts: [String: RegisteredGlobalShortcut] = [:]
  private var shortcutIDsByCarbonID: [UInt32: String] = [:]
  private var nextHotKeyID: UInt32 = 1
  
  func applicationDidFinishLaunching(_ notification: Notification) {
    writeDebugLog("applicationDidFinishLaunching start")
    SettingsStore.shared.load()
    applyThemePreference()
    setupMainMenu()
    setupStatusItem()
    syncHotkeySettings()
    
    // Show gallery on launch
    showGallery()
    writeDebugLog("applicationDidFinishLaunching end")
  }
  
  func applicationWillTerminate(_ notification: Notification) {
    unregisterAllGlobalShortcuts()
    if let hotkeyEventHandler = hotkeyEventHandler {
      RemoveEventHandler(hotkeyEventHandler)
      self.hotkeyEventHandler = nil
    }
  }
  
  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
  
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }
  
  func applyThemePreference() {
    let appearanceName = SettingsStore.shared.appKitAppearanceName
    let apply = {
      NSApp.appearance = appearanceName.flatMap { NSAppearance(named: $0) }
    }
    
    if Thread.isMainThread {
      apply()
    } else {
      DispatchQueue.main.async(execute: apply)
    }
  }
  
  // MARK: - Main Menu (built programmatically; replaces the legacy MainMenu.xib)
  func setupMainMenu() {
    let mainMenu = NSMenu()

    // Application menu
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "About QPARK Shot", action: #selector(showAboutAction), keyEquivalent: "")
    appMenu.addItem(.separator())
    let prefs = appMenu.addItem(withTitle: "Preferences…", action: #selector(showPreferencesWindow(_:)), keyEquivalent: ",")
    prefs.keyEquivalentModifierMask = [.command]
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide QPARK Shot", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(withTitle: "Quit QPARK Shot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appMenuItem.submenu = appMenu

    // Edit menu (standard text editing shortcuts: undo/redo/cut/copy/paste/select-all)
    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editMenuItem.submenu = editMenu

    // Window menu
    let windowMenuItem = NSMenuItem()
    mainMenu.addItem(windowMenuItem)
    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    windowMenu.addItem(withTitle: "Gallery", action: #selector(showGalleryAction), keyEquivalent: "g")
    windowMenuItem.submenu = windowMenu

    NSApp.mainMenu = mainMenu
    NSApp.windowsMenu = windowMenu
  }

  // MARK: - Status Bar Icon
  func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusItem?.button {
      let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "QPARK Shot")
      button.image = image
    }
    
    let menu = NSMenu()
    
    let captureItem = NSMenuItem(title: "Capture Selected Area...", action: #selector(triggerCaptureAction), keyEquivalent: "c")
    captureItem.keyEquivalentModifierMask = [.command, .shift]
    menu.addItem(captureItem)
    
    let galleryItem = NSMenuItem(title: "Open Gallery", action: #selector(showGalleryAction), keyEquivalent: "g")
    galleryItem.keyEquivalentModifierMask = [.command]
    menu.addItem(galleryItem)
    
    let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferencesWindow(_:)), keyEquivalent: ",")
    preferencesItem.keyEquivalentModifierMask = [.command]
    menu.addItem(preferencesItem)
    
    menu.addItem(NSMenuItem.separator())
    
    let aboutItem = NSMenuItem(title: "About QPARK Shot", action: #selector(showAboutAction), keyEquivalent: "")
    menu.addItem(aboutItem)
    
    let quitItem = NSMenuItem(title: "Quit QPARK Shot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quitItem.keyEquivalentModifierMask = [.command]
    menu.addItem(quitItem)
    
    statusItem?.menu = menu
  }
  
  @objc func triggerCaptureAction(_ sender: Any?) {
    triggerCaptureFlow()
  }
  
  @objc func showGalleryAction(_ sender: Any?) {
    showGallery()
  }
  
  @objc func showPreferencesWindow(_ sender: Any?) {
    showSettings()
  }
  
  @objc func showAboutAction(_ sender: Any?) {
    NSApp.orderFrontStandardAboutPanel(nil)
  }
  
  // MARK: - Native Windows
  func showGallery() {
    MainWindowNavigation.shared.showGallery()
    focusMainWindow(preferredContentSize: CGSize(width: 760, height: 520))
  }
  
  func showSettings() {
    MainWindowNavigation.shared.showSettings()
    focusMainWindow(preferredContentSize: CGSize(width: 760, height: 520))
  }
  
  func openEditor(for imagePath: String) {
    MainWindowNavigation.shared.openEditor(imagePath)
    focusMainWindow(preferredContentSize: CGSize(width: 900, height: 650))
  }
  
  private func focusMainWindow(preferredContentSize: CGSize) {
    let window: NSWindow
    if let existingWindow = galleryWindow ?? existingMainWindow() {
      window = existingWindow
      galleryWindow = existingWindow
    } else {
      let createdWindow = makeMainWindow(contentSize: preferredContentSize)
      galleryWindow = createdWindow
      window = createdWindow
    }
    
    let contentSize = window.contentView?.bounds.size ?? .zero
    if contentSize.width < preferredContentSize.width ||
        contentSize.height < preferredContentSize.height {
      window.setContentSize(
        CGSize(
          width: max(contentSize.width, preferredContentSize.width),
          height: max(contentSize.height, preferredContentSize.height)
        )
      )
    }
    
    window.delegate = self
    window.title = "QPARK Shot"
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  // MARK: - Window close confirmation
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    let alert = NSAlert()
    alert.messageText = "Quit QPARK Shot?"
    alert.informativeText = "Are you sure you want to close the app?"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Quit")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn {
      NSApp.terminate(nil)
    }
    return false
  }
  
  private func existingMainWindow() -> NSWindow? {
    if let identifiedWindow = NSApp.windows.first(where: { $0.identifier == MainAppWindow.mainWindowIdentifier }) {
      return identifiedWindow
    }
    return NSApp.windows.first(where: { $0 is MainAppWindow })
  }
  
  private func makeMainWindow(contentSize: CGSize) -> NSWindow {
    let window = MainAppWindow(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.installRootContent()
    window.center()
    return window
  }
  
  // MARK: - Capture Flow
  func triggerCaptureFlow() {
    guard CGPreflightScreenCaptureAccess() else {
      let req = CGRequestScreenCaptureAccess()
      writeDebugLog("Request screen capture access returned: \(req)")
      
      // Attempt legacy prompt or Settings redirection if repeat request
      if #available(macOS 12.3, *) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] _, _ in
          DispatchQueue.main.async {
            if Self.hasRequestedScreenCapturePermissionInSession {
              self?.openScreenRecordingSettings()
            }
            Self.hasRequestedScreenCapturePermissionInSession = true
          }
        }
      } else {
        if Self.hasRequestedScreenCapturePermissionInSession {
          openScreenRecordingSettings()
        }
        Self.hasRequestedScreenCapturePermissionInSession = true
      }
      return
    }
    
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("qpark-shot-\(UUID().uuidString)")
      .appendingPathExtension("png")
    
    let mainWindowWasVisible = galleryWindow?.isVisible ?? false
    
    galleryWindow?.orderOut(nil)
    
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }
      
      Thread.sleep(forTimeInterval: 0.25)
      
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
      process.arguments = ["-i", url.path]
      
      do {
        try process.run()
        process.waitUntilExit()
        
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        
        DispatchQueue.main.async {
          if !fileExists {
            if mainWindowWasVisible {
              self.galleryWindow?.makeKeyAndOrderFront(nil)
              NSApp.activate(ignoringOtherApps: true)
            }
            return
          }
          
          self.openEditor(for: url.path)
        }
      } catch {
        self.writeDebugLog("Screencapture run error: \(error.localizedDescription)")
        DispatchQueue.main.async {
          if mainWindowWasVisible {
            self.galleryWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
          }
        }
      }
    }
  }
  
  private func openScreenRecordingSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
      NSWorkspace.shared.open(url)
    }
  }
  
  // MARK: - Carbon Global Hotkey Handling
  func syncHotkeySettings() {
    unregisterAllGlobalShortcuts()
    
    let key = "flutter.qpark_shot.app_settings.v1"
    guard let jsonString = UserDefaults.standard.string(forKey: key),
          let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let hotkey = json["hotkey"] as? [String: Any],
          let enabled = hotkey["enabled"] as? Bool, enabled,
          let keyChar = hotkey["key"] as? String, !keyChar.isEmpty,
          let keyCode = keyCode(for: keyChar) else {
        return
      }
    
    var modifiers: UInt32 = 0
    if let modifierList = hotkey["modifiers"] as? [String] {
      for modifierName in modifierList {
        switch modifierName.lowercased() {
        case "control", "ctrl":
          modifiers |= UInt32(controlKey)
        case "shift":
          modifiers |= UInt32(shiftKey)
        case "alt", "option":
          modifiers |= UInt32(optionKey)
        case "meta", "cmd", "command":
          modifiers |= UInt32(cmdKey)
        default:
          break
        }
      }
    }
    
    let handlerStatus = ensureHotkeyEventHandlerInstalled()
    guard handlerStatus == noErr else { return }
    
    let carbonID = nextAvailableHotKeyID()
    let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: carbonID)
    var hotKeyRef: EventHotKeyRef?
    
    let status = RegisterEventHotKey(
      keyCode,
      modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      OptionBits(0),
      &hotKeyRef)
      
    if status == noErr, let hotKeyRef = hotKeyRef {
      let id = "captureDesktop"
      registeredGlobalShortcuts[id] = RegisteredGlobalShortcut(
        id: id,
        carbonID: carbonID,
        ref: hotKeyRef)
      shortcutIDsByCarbonID[carbonID] = id
    }
  }
  
  private func ensureHotkeyEventHandlerInstalled() -> OSStatus {
    if hotkeyEventHandler != nil {
      return noErr
    }
    
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed))
    return InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event = event, let userData = userData else {
          return OSStatus(eventNotHandledErr)
        }
        
        let appDelegate = Unmanaged<AppDelegate>
          .fromOpaque(userData)
          .takeUnretainedValue()
        return appDelegate.handleHotkeyEvent(event)
      },
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &hotkeyEventHandler)
  }
  
  private func handleHotkeyEvent(_ event: EventRef) -> OSStatus {
    var hotKeyID = EventHotKeyID(signature: 0, id: 0)
    let status = GetEventParameter(
      event,
      EventParamName(kEventParamDirectObject),
      EventParamType(typeEventHotKeyID),
      nil,
      MemoryLayout<EventHotKeyID>.size,
      nil,
      &hotKeyID)
    guard status == noErr else {
      return status
    }
    
    guard hotKeyID.signature == Self.hotKeySignature,
          let _ = shortcutIDsByCarbonID[hotKeyID.id]
    else {
      return OSStatus(eventNotHandledErr)
    }
    
    DispatchQueue.main.async { [weak self] in
      self?.triggerCaptureFlow()
    }
    return noErr
  }
  
  private func unregisterAllGlobalShortcuts() {
    for shortcut in registeredGlobalShortcuts.values {
      UnregisterEventHotKey(shortcut.ref)
    }
    registeredGlobalShortcuts.removeAll()
    shortcutIDsByCarbonID.removeAll()
  }
  
  private func nextAvailableHotKeyID() -> UInt32 {
    while shortcutIDsByCarbonID[nextHotKeyID] != nil {
      nextHotKeyID += 1
    }
    let carbonID = nextHotKeyID
    nextHotKeyID += 1
    return carbonID
  }
  
  private func keyCode(for key: String) -> UInt32? {
    switch key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
    case "A": return UInt32(kVK_ANSI_A)
    case "B": return UInt32(kVK_ANSI_B)
    case "C": return UInt32(kVK_ANSI_C)
    case "D": return UInt32(kVK_ANSI_D)
    case "E": return UInt32(kVK_ANSI_E)
    case "F": return UInt32(kVK_ANSI_F)
    case "G": return UInt32(kVK_ANSI_G)
    case "H": return UInt32(kVK_ANSI_H)
    case "I": return UInt32(kVK_ANSI_I)
    case "J": return UInt32(kVK_ANSI_J)
    case "K": return UInt32(kVK_ANSI_K)
    case "L": return UInt32(kVK_ANSI_L)
    case "M": return UInt32(kVK_ANSI_M)
    case "N": return UInt32(kVK_ANSI_N)
    case "O": return UInt32(kVK_ANSI_O)
    case "P": return UInt32(kVK_ANSI_P)
    case "Q": return UInt32(kVK_ANSI_Q)
    case "R": return UInt32(kVK_ANSI_R)
    case "S": return UInt32(kVK_ANSI_S)
    case "T": return UInt32(kVK_ANSI_T)
    case "U": return UInt32(kVK_ANSI_U)
    case "V": return UInt32(kVK_ANSI_V)
    case "W": return UInt32(kVK_ANSI_W)
    case "X": return UInt32(kVK_ANSI_X)
    case "Y": return UInt32(kVK_ANSI_Y)
    case "Z": return UInt32(kVK_ANSI_Z)
    case "0": return UInt32(kVK_ANSI_0)
    case "1": return UInt32(kVK_ANSI_1)
    case "2": return UInt32(kVK_ANSI_2)
    case "3": return UInt32(kVK_ANSI_3)
    case "4": return UInt32(kVK_ANSI_4)
    case "5": return UInt32(kVK_ANSI_5)
    case "6": return UInt32(kVK_ANSI_6)
    case "7": return UInt32(kVK_ANSI_7)
    case "8": return UInt32(kVK_ANSI_8)
    case "9": return UInt32(kVK_ANSI_9)
    default: return nil
    }
  }
  
  private func writeDebugLog(_ message: String) {
    let logFile = "/tmp/qpark_shot_debug.log"
    let logMessage = "\(Date()): \(message)\n"
    print(message)
    if let data = logMessage.data(using: .utf8) {
      if let fileHandle = FileHandle(forWritingAtPath: logFile) {
        fileHandle.seekToEndOfFile()
        fileHandle.write(data)
        fileHandle.closeFile()
      } else {
        try? data.write(to: URL(fileURLWithPath: logFile))
      }
    }
  }
}
