import Cocoa
import Carbon
import SwiftUI
import ScreenCaptureKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  static var current: AppDelegate? {
    NSApp.delegate as? AppDelegate
  }

  static var shared: AppDelegate {
    guard let delegate = NSApp.delegate as? AppDelegate else {
      preconditionFailure("AppDelegate is not installed")
    }
    return delegate
  }
  
  nonisolated private static let hotKeySignature = OSType(0x51504B53) // "QPKS"
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
  private var cleanupSchedulerTask: Task<Void, Never>?
  private var isCleaning = false
  
  func applicationDidFinishLaunching(_ notification: Notification) {
    writeDebugLog("applicationDidFinishLaunching start")
    _ = SettingsStore.shared
    if AppTestEnvironment.isEnabled,
       !ProcessInfo.processInfo.arguments.contains("--ui-test-scenario") { return }
    applyThemePreference()
    setupMainMenu()
    setupStatusItem()
    if !AppTestEnvironment.isEnabled { syncHotkeySettings() }
    
    // Show gallery on launch
    showGallery()
    if !AppTestEnvironment.isEnabled { startCleanupScheduler() }
    writeDebugLog("applicationDidFinishLaunching end")
  }
  
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !AppTestEnvironment.isEnabled,
          ShotQueueStore.shared.temporaryItemCount > 0 || EditorDraftStore.shared.drafts.values.contains(where: \.isDirty) else {
      return .terminateNow
    }
    let alert = NSAlert()
    alert.messageText = localized("common.quit")
    alert.informativeText = localized("workspace.clear_session_message")
    alert.addButton(withTitle: localized("common.quit"))
    alert.addButton(withTitle: localized("common.cancel"))
    return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
  }

  func applicationWillTerminate(_ notification: Notification) {
    SettingsStore.shared.flushPendingPersistence()
    cleanupSchedulerTask?.cancel()
    cleanupSchedulerTask = nil
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
    NSApp.appearance = appearanceName.flatMap { NSAppearance(named: $0) }
  }
  
  // MARK: - Main Menu (built programmatically; replaces the legacy MainMenu.xib)
  func setupMainMenu() {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: localized("menu.about"), action: #selector(showAboutAction), keyEquivalent: "")
    appMenu.addItem(.separator())
    let prefs = appMenu.addItem(withTitle: localized("common.preferences"), action: #selector(showPreferencesWindow(_:)), keyEquivalent: ",")
    prefs.keyEquivalentModifierMask = [.command]
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: localized("menu.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(withTitle: localized("common.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appMenuItem.submenu = appMenu

    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    let editMenu = NSMenu(title: localized("menu.edit"))
    editMenu.addItem(withTitle: localized("editor.undo"), action: Selector(("undo:")), keyEquivalent: "z")
    let redo = editMenu.addItem(withTitle: localized("editor.redo"), action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: localized("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: localized("common.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: localized("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: localized("menu.select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editMenuItem.submenu = editMenu

    let windowMenuItem = NSMenuItem()
    mainMenu.addItem(windowMenuItem)
    let windowMenu = NSMenu(title: localized("menu.window"))
    windowMenu.addItem(withTitle: localized("menu.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    windowMenu.addItem(withTitle: localized("workspace.library"), action: #selector(showGalleryAction), keyEquivalent: "g")
    windowMenuItem.submenu = windowMenu

    NSApp.mainMenu = mainMenu
    NSApp.windowsMenu = windowMenu
  }

  func rebuildLocalizedSurfaces() {
    setupMainMenu()
    setupStatusItem()
    galleryWindow?.title = localized("app.name")
    PreferencesWindowController.shared.refreshLocalizedChrome()
  }

  @MainActor
  func scheduleCleanupRun() {
    Task { [weak self] in
      await self?.performCleanup()
    }
  }

  @MainActor
  private func startCleanupScheduler() {
    cleanupSchedulerTask?.cancel()
    scheduleCleanupRun()
    cleanupSchedulerTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30 * 60))
        guard !Task.isCancelled else { return }
        await self?.performCleanup()
      }
    }
  }

  @MainActor
  private func performCleanup() async {
    guard !isCleaning else { return }
    isCleaning = true
    defer { isCleaning = false }
    let settings = SettingsStore.shared
    let policy = settings.cleanupPolicy
    guard policy.mode == .afterDuration else { return }

    let workspace = WorkspaceStore.shared
    let report = await CleanupService.shared.run(
      policy: policy,
      galleryEntries: Array(GalleryIndexStore.shared.entries.values),
      activePaths: workspace.cleanupActivePaths,
      temporaryRoots: [captureScratchFolderURL(), storageFolderURL(isTemporary: true)],
      savedRoots: galleryStorageFolderCandidates(
        saveDirectory: settings.saveDirectory,
        bookmarkData: settings.saveDirectoryBookmarkData
      ),
      allowsMutation: { url, isSaved in
        let currentPolicy = SettingsStore.shared.cleanupPolicy
        guard currentPolicy == policy else { return false }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let protected = WorkspaceStore.shared.cleanupActivePaths.contains {
          URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path == path
        }
        let favorite = GalleryIndexStore.shared.entries.values.contains {
          $0.favorite && URL(fileURLWithPath: $0.path).standardizedFileURL.resolvingSymlinksInPath().path == path
        }
        return !protected && (!isSaved || !favorite)
      }
    )

    for path in report.trashedSavedPaths {
      GalleryIndexStore.shared.forget(path: path)
    }
    if report.changedAnything {
      workspace.presentStatus(
        localized(report.failures.isEmpty ? "status.cleanup_completed" : "status.cleanup_failed"),
        kind: report.failures.isEmpty ? .success : .warning
      )
      workspace.loadLibrary()
    } else if !report.failures.isEmpty {
      workspace.presentStatus(localized("status.cleanup_failed"), kind: .error)
    }
  }

  // MARK: - Status Bar Icon
  func setupStatusItem() {
    if statusItem == nil {
      statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }
    if let button = statusItem?.button {
      let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: localized("app.name"))
      button.image = image
    }
    
    let menu = NSMenu()
    
    let captureItem = NSMenuItem(title: localized("capture.selected_area"), action: #selector(triggerCaptureAction), keyEquivalent: "")
    applyMenuShortcut(SettingsStore.shared.selectionHotkey, to: captureItem)
    menu.addItem(captureItem)

    let fullScreenItem = NSMenuItem(title: localized("capture.full_screen"), action: #selector(triggerFullScreenCaptureAction), keyEquivalent: "")
    applyMenuShortcut(SettingsStore.shared.fullScreenHotkey, to: fullScreenItem)
    menu.addItem(fullScreenItem)

    let windowItem = NSMenuItem(title: localized("capture.window"), action: #selector(triggerWindowCaptureAction), keyEquivalent: "")
    menu.addItem(windowItem)

    let repeatAreaItem = NSMenuItem(title: localized("capture.repeat_area"), action: #selector(triggerRepeatAreaCaptureAction), keyEquivalent: "")
    menu.addItem(repeatAreaItem)

    let delayItem = NSMenuItem(title: localized("capture.with_delay"), action: nil, keyEquivalent: "")
    let delayMenu = NSMenu()
    for seconds in [3, 5, 10] {
      let item = NSMenuItem(
        title: LocalizationController.shared.format("capture.seconds_format", seconds),
        action: #selector(triggerDelayedCaptureAction(_:)),
        keyEquivalent: ""
      )
      item.tag = seconds
      delayMenu.addItem(item)
    }
    delayItem.submenu = delayMenu
    menu.addItem(delayItem)

    menu.addItem(NSMenuItem.separator())

    let galleryItem = NSMenuItem(title: localized("workspace.library"), action: #selector(showGalleryAction), keyEquivalent: "g")
    galleryItem.keyEquivalentModifierMask = [.command]
    menu.addItem(galleryItem)
    
    let preferencesItem = NSMenuItem(title: localized("common.preferences"), action: #selector(showPreferencesWindow(_:)), keyEquivalent: ",")
    preferencesItem.keyEquivalentModifierMask = [.command]
    menu.addItem(preferencesItem)
    
    menu.addItem(NSMenuItem.separator())
    
    let aboutItem = NSMenuItem(title: localized("menu.about"), action: #selector(showAboutAction), keyEquivalent: "")
    menu.addItem(aboutItem)
    
    let quitItem = NSMenuItem(title: localized("common.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quitItem.keyEquivalentModifierMask = [.command]
    menu.addItem(quitItem)
    
    statusItem?.menu = menu
  }
  
  @MainActor
  @objc func triggerCaptureAction(_ sender: Any?) {
    triggerCaptureFlow()
  }

  @MainActor
  @objc func triggerFullScreenCaptureAction(_ sender: Any?) {
    triggerCaptureFlow(modeOverride: "fullScreen")
  }

  @MainActor
  @objc func triggerWindowCaptureAction(_ sender: Any?) {
    triggerCaptureFlow(modeOverride: "window")
  }

  @MainActor
  @objc func triggerRepeatAreaCaptureAction(_ sender: Any?) {
    triggerCaptureFlow(modeOverride: "repeatLastArea")
  }

  @MainActor
  @objc func triggerDelayedCaptureAction(_ sender: Any?) {
    let seconds = (sender as? NSMenuItem)?.tag ?? 3
    triggerCaptureFlow(delayOverride: seconds)
  }
  
  @MainActor
  @objc func showGalleryAction(_ sender: Any?) {
    showGallery()
  }
  
  @MainActor
  @objc func showPreferencesWindow(_ sender: Any?) {
    showSettings()
  }
  
  @objc func showAboutAction(_ sender: Any?) {
    PreferencesWindowController.shared.show(about: true)
  }
  
  // MARK: - Native Windows
  @MainActor
  func showGallery() {
    MainWindowNavigation.shared.showGallery()
    focusMainWindow(preferredContentSize: CGSize(width: 1280, height: 800))
  }
  
  @MainActor
  func showSettings() {
    PreferencesWindowController.shared.show()
  }
  
  @MainActor
  func openEditor(forPath imagePath: String) {
    let item = ShotQueueStore.shared.enqueue(path: imagePath)
    openEditor(itemID: item.id)
  }

  @MainActor
  func showQuickAction(forPath imagePath: String) {
    let item = ShotQueueStore.shared.enqueue(path: imagePath)
    MainWindowNavigation.shared.showQuickAction(itemID: item.id)
    focusMainWindow(preferredContentSize: CGSize(width: 1280, height: 800))
  }

  @MainActor
  func openEditor(itemID: UUID) {
    MainWindowNavigation.shared.openEditor(itemID: itemID)
    focusMainWindow(preferredContentSize: CGSize(width: 1280, height: 800))
  }
  
  @MainActor
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
    
    window.delegate = self
    window.title = localized("app.name")
    if let size = AppTestEnvironment.value("QPARK_TEST_WINDOW_SIZE") {
      let dimensions = size.split(separator: "x").compactMap { Double($0) }
      if dimensions.count == 2 {
        // Apply the fixture size after SwiftUI has presented its split columns.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak window] in
          guard let window else { return }
          window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: dimensions[0], height: dimensions[1])), display: true)
        }
      }
    }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  // MARK: - Window close confirmation
  @MainActor
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
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
    if let visible = NSScreen.main?.visibleFrame {
      var frame = window.frame
      frame.size.width = min(frame.width, visible.width)
      frame.size.height = min(frame.height, visible.height)
      window.setFrame(frame, display: false)
    }
    window.center()
    return window
  }
  
  // MARK: - Capture Flow
  /// Triggers a capture. Pass `modeOverride` / `delayOverride` for one-shot menu actions
  /// without mutating saved settings.
  @MainActor
  func triggerCaptureFlow(modeOverride: String? = nil, delayOverride: Int? = nil) {
    let workspace = WorkspaceStore.shared
    guard !workspace.isCapturing else { return }
    workspace.isCapturing = true
    workspace.presentStatus(localized("status.capturing"), autoDismiss: false)

    guard CGPreflightScreenCaptureAccess() else {
      workspace.isCapturing = false
      let req = CGRequestScreenCaptureAccess()
      writeDebugLog("Request screen capture access returned: \(req)")
      workspace.showPermissionRequired()
      focusMainWindow(preferredContentSize: CGSize(width: 1280, height: 800))

      SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { _, _ in
        Task { @MainActor in
            if Self.hasRequestedScreenCapturePermissionInSession {
              AppDelegate.shared.openScreenRecordingSettings()
            }
            Self.hasRequestedScreenCapturePermissionInSession = true
        }
      }
      return
    }

    let mainWindowWasVisible = galleryWindow?.isVisible ?? false

    galleryWindow?.orderOut(nil)

    let store = SettingsStore.shared
    let mode = CaptureMode(rawValue: modeOverride ?? store.captureMode) ?? .selection
    let delaySeconds = max(0, delayOverride ?? store.captureDelaySeconds)

    if mode == .repeatLastArea, store.lastCaptureRegion == nil {
      RegionSelectionController.shared.selectRegion { [weak self] region in
        guard let self else { return }
        guard let region else {
          WorkspaceStore.shared.isCapturing = false
          WorkspaceStore.shared.presentStatus(localized("status.capture_cancelled"))
          self.restoreMainWindowIfNeeded(mainWindowWasVisible)
          return
        }
        store.lastCaptureRegion = region
        store.save()
        self.runCapture(
          mode: .repeatLastArea,
          delaySeconds: delaySeconds,
          repeatRegion: region,
          restoreMainWindowOnCancel: mainWindowWasVisible
        )
      }
      return
    }

    runCapture(
      mode: mode,
      delaySeconds: delaySeconds,
      repeatRegion: store.lastCaptureRegion,
      restoreMainWindowOnCancel: mainWindowWasVisible
    )
  }

  @MainActor
  private func runCapture(
    mode: CaptureMode,
    delaySeconds: Int,
    repeatRegion: CaptureRegion?,
    restoreMainWindowOnCancel: Bool
  ) {
    let outputURL = CaptureService.shared.makeTemporaryOutputURL()
    let request = CaptureRequest(
      mode: mode,
      delaySeconds: delaySeconds,
      outputURL: outputURL,
      repeatRegion: repeatRegion
    )

    CaptureService.shared.capture(request) { [weak self] result in
      Task { @MainActor in
        guard let self else { return }

        switch result {
        case .success(let url):
          WorkspaceStore.shared.isCapturing = false
          WorkspaceStore.shared.captured(path: url.path)
          self.focusMainWindow(preferredContentSize: CGSize(width: 1280, height: 800))
        case .failure(let error):
          WorkspaceStore.shared.isCapturing = false
          self.writeDebugLog("Screencapture error: \(error)")
          if error == .cancelledOrEmpty {
            WorkspaceStore.shared.presentStatus(localized("status.capture_cancelled"), kind: .info)
            self.restoreMainWindowIfNeeded(restoreMainWindowOnCancel)
          } else {
            WorkspaceStore.shared.showError(localized("status.capture_failed"))
            self.focusMainWindow(preferredContentSize: CGSize(width: 1280, height: 800))
          }
        }
      }
    }
  }

  @MainActor
  private func restoreMainWindowIfNeeded(_ shouldRestore: Bool) {
    guard shouldRestore else { return }
    galleryWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  
  func openScreenRecordingSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
      NSWorkspace.shared.open(url)
    }
  }
  
  // MARK: - Carbon Global Hotkey Handling
  func syncHotkeySettings() {
    unregisterAllGlobalShortcuts()
    guard !AppTestEnvironment.isEnabled else { return }

    let handlerStatus = ensureHotkeyEventHandlerInstalled()
    guard handlerStatus == noErr else { return }

    let settings = SettingsStore.shared.snapshot()
    if settings.hotkey.validationError(comparedWith: settings.fullScreenHotkey) == nil {
      registerHotkey(from: settings.hotkey, id: "captureSelection")
    }
    if settings.fullScreenHotkey.validationError(comparedWith: settings.hotkey) == nil {
      registerHotkey(from: settings.fullScreenHotkey, id: "captureFullScreen")
    }
  }

  private func registerHotkey(from hotkey: HotkeySettings, id: String) {
    guard hotkey.enabled,
          hotkey.validationError() == nil,
          let keyCode = keyCode(for: hotkey.key) else {
      return
    }

    var modifiers: UInt32 = 0
    for modifierName in hotkey.modifiers {
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
      registeredGlobalShortcuts[id] = RegisteredGlobalShortcut(
        id: id,
        carbonID: carbonID,
        ref: hotKeyRef)
      shortcutIDsByCarbonID[carbonID] = id
    }
  }

  private func applyMenuShortcut(_ shortcut: HotkeySettings, to item: NSMenuItem) {
    guard shortcut.enabled, shortcut.validationError() == nil else { return }
    item.keyEquivalent = shortcut.normalizedKey.lowercased()
    var mask: NSEvent.ModifierFlags = []
    for modifier in shortcut.normalizedModifiers {
      switch modifier {
      case "command": mask.insert(.command)
      case "control": mask.insert(.control)
      case "option": mask.insert(.option)
      case "shift": mask.insert(.shift)
      default: break
      }
    }
    item.keyEquivalentModifierMask = mask
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
  
  nonisolated private func handleHotkeyEvent(_ event: EventRef) -> OSStatus {
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
    
    guard hotKeyID.signature == Self.hotKeySignature else {
      return OSStatus(eventNotHandledErr)
    }

    let carbonID = hotKeyID.id
    Task { @MainActor [weak self] in
      guard let shortcutID = self?.shortcutIDsByCarbonID[carbonID] else { return }
      switch shortcutID {
      case "captureFullScreen":
        self?.triggerCaptureFlow(modeOverride: "fullScreen")
      default:
        self?.triggerCaptureFlow(modeOverride: "selection")
      }
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
