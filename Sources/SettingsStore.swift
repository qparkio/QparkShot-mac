import Cocoa
import SwiftUI

struct SettingsEffects: OptionSet, Equatable {
  let rawValue: Int

  static let appearance = SettingsEffects(rawValue: 1 << 0)
  static let localization = SettingsEffects(rawValue: 1 << 1)
  static let hotkeys = SettingsEffects(rawValue: 1 << 2)
  static let localizedChrome = SettingsEffects(rawValue: 1 << 3)
  static let cleanup = SettingsEffects(rawValue: 1 << 4)
  static let library = SettingsEffects(rawValue: 1 << 5)
}

enum SettingsChange: Equatable {
  case appearance
  case localization
  case shortcuts
  case capture
  case export
  case watermark
  case cleanup
  case library
  case all

  var effects: SettingsEffects {
    switch self {
    case .appearance: return .appearance
    case .localization: return [.localization, .localizedChrome]
    case .shortcuts: return [.hotkeys, .localizedChrome]
    case .cleanup: return .cleanup
    case .library: return .library
    case .capture, .export, .watermark: return []
    case .all: return [.appearance, .localization, .hotkeys, .localizedChrome, .cleanup, .library]
    }
  }
}

final class SettingsStore: ObservableObject {
  static let shared = SettingsStore()

  @Published var themePreference: String = "system"
  @Published var hotkeyEnabled: Bool = true
  @Published var hotkeyKey: String = "C"
  @Published var hotkeyModifiers: [String] = ["command", "shift"]
  @Published var watermarkTextEnabled: Bool = false
  @Published var watermarkText: String = "QPARK Shot"
  @Published var watermarkTextColor: String = "#FFFFFF"
  @Published var watermarkLogoEnabled: Bool = false
  @Published var watermarkLogoPath: String = ""
  @Published var watermarkLogoBookmarkData: Data? = nil
  @Published var watermarkOpacity: Double = 0.5
  @Published var watermarkSize: Double = 120.0
  @Published var watermarkPosition: String = "bottomRight"
  @Published var watermarkLayoutMode: String = "single"
  @Published var watermarkSpacing: Double = 150.0
  @Published var watermarkTilePattern: String = "aligned"
  @Published var watermarkTileRandomness: Double = 0.45
  @Published var cleanupMode: String = "never"
  @Published var cleanupIncludeSaved: Bool = false
  @Published var cleanupDurationHours: Double = 24
  @Published var saveDirectory: String = ""
  @Published var saveDirectoryBookmarkData: Data? = nil
  @Published var queuePanelEnabled: Bool = true
  @Published var captureMode: String = "selection"
  @Published var captureDelaySeconds: Int = 0
  @Published var fullScreenHotkeyEnabled: Bool = false
  @Published var fullScreenHotkeyKey: String = "F"
  @Published var fullScreenHotkeyModifiers: [String] = ["command", "shift"]
  @Published var exportPresetID: String = ExportPreset.watermarked.id
  @Published var filenameTemplate: String = "{date}_{time}_{preset}"
  @Published var defaultQuickAction: String = "edit"
  @Published var galleryOCREnabled: Bool = true
  @Published var gallerySearchIndexEnabled: Bool = true
  @Published var lastCaptureRegion: CaptureRegion? = nil
  @Published var appLanguageCode: String = AppLanguage.preferredDefault().rawValue
  @Published var textRecognitionLanguageCodes: [String] = LocalizationSettings().textRecognitionLanguageCodes

  private var pendingPersistence: DispatchWorkItem?
  private let defaults: UserDefaults

  var preferredColorScheme: ColorScheme? {
    switch themePreference {
    case "light":
      return .light
    case "dark":
      return .dark
    default:
      return nil
    }
  }

  var appKitAppearanceName: NSAppearance.Name? {
    switch themePreference {
    case "light":
      return .aqua
    case "dark":
      return .darkAqua
    default:
      return nil
    }
  }

  var cleanupPolicy: CleanupPolicy {
    CleanupPolicy(
      mode: CleanupMode(rawValue: cleanupMode) ?? .never,
      maxAge: max(cleanupDurationHours, 1) * 3600,
      includeSavedFiles: cleanupIncludeSaved
    )
  }

  var selectionHotkey: HotkeySettings {
    HotkeySettings(
      enabled: hotkeyEnabled,
      key: hotkeyKey,
      modifiers: hotkeyModifiers
    )
  }

  var fullScreenHotkey: HotkeySettings {
    HotkeySettings(
      enabled: fullScreenHotkeyEnabled,
      key: fullScreenHotkeyKey,
      modifiers: fullScreenHotkeyModifiers
    )
  }

  private init() {
    if ProcessInfo.processInfo.arguments.contains("--ui-test-scenario"),
       let isolatedDefaults = UserDefaults(suiteName: "com.qpark.shot.ui-tests") {
      isolatedDefaults.removePersistentDomain(forName: "com.qpark.shot.ui-tests")
      defaults = isolatedDefaults
    } else {
      defaults = .standard
    }
    load()
  }

  func load() {
    apply(SettingsStorage.load(defaults: defaults))
  }

  func snapshot() -> AppSettings {
    AppSettings(
      themePreference: themePreference,
      hotkey: HotkeySettings(
        enabled: hotkeyEnabled,
        key: hotkeyKey,
        modifiers: hotkeyModifiers
      ),
      watermark: WatermarkSettings(
        layoutMode: watermarkLayoutMode,
        spacing: watermarkSpacing,
        tilePattern: watermarkTilePattern,
        tileRandomness: watermarkTileRandomness,
        text: WatermarkTextSettings(
          enabled: watermarkTextEnabled,
          text: watermarkText,
          color: watermarkTextColor
        ),
        logo: WatermarkLogoSettings(
          enabled: watermarkLogoEnabled,
          path: watermarkLogoPath,
          bookmarkData: watermarkLogoBookmarkData,
          size: watermarkSize,
          opacity: watermarkOpacity,
          positionMode: watermarkPosition
        )
      ),
      cleanup: CleanupSettings(
        mode: cleanupMode,
        includeSavedFiles: cleanupIncludeSaved,
        durationSeconds: cleanupDurationHours * 3600.0,
        saveDirectory: saveDirectory,
        saveDirectoryBookmarkData: saveDirectoryBookmarkData
      ),
      queue: QueueSettings(panelEnabled: queuePanelEnabled),
      capture: CaptureSettings(
        mode: captureMode,
        delaySeconds: captureDelaySeconds,
        lastRegion: lastCaptureRegion
      ),
      fullScreenHotkey: HotkeySettings(
        enabled: fullScreenHotkeyEnabled,
        key: fullScreenHotkeyKey,
        modifiers: fullScreenHotkeyModifiers
      ),
      export: ExportSettings(
        selectedPresetID: exportPresetID,
        filenameTemplate: filenameTemplate,
        defaultQuickAction: defaultQuickAction
      ),
      gallery: GallerySettings(
        ocrEnabled: galleryOCREnabled,
        searchIndexEnabled: gallerySearchIndexEnabled
      ),
      localization: LocalizationSettings(
        appLanguageCode: appLanguageCode,
        textRecognitionLanguageCodes: textRecognitionLanguageCodes
      )
    )
  }

  @MainActor
  func save() {
    save(change: .all)
  }

  @MainActor
  func save(change: SettingsChange, debounce: Bool = false) {
    persist(debounce: debounce)
    let effects = change.effects

    if effects.contains(.localization) {
      LocalizationController.shared.refreshFromSettings()
    }
    if effects.contains(.hotkeys) {
      AppDelegate.current?.syncHotkeySettings()
    }
    if effects.contains(.appearance) {
      AppDelegate.current?.applyThemePreference()
    }
    if effects.contains(.localizedChrome) {
      AppDelegate.current?.rebuildLocalizedSurfaces()
    }
    if effects.contains(.cleanup) {
      AppDelegate.current?.scheduleCleanupRun()
    }
    if effects.contains(.library) {
      WorkspaceStore.shared.loadLibrary()
    }
  }

  @MainActor
  private func persist(debounce: Bool) {
    pendingPersistence?.cancel()

    guard debounce else {
      SettingsStorage.save(snapshot(), defaults: defaults)
      pendingPersistence = nil
      return
    }

    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      SettingsStorage.save(self.snapshot(), defaults: self.defaults)
      self.pendingPersistence = nil
    }
    pendingPersistence = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
  }

  private func apply(_ settings: AppSettings) {
    themePreference = settings.themePreference
    hotkeyEnabled = settings.hotkey.enabled
    hotkeyKey = settings.hotkey.key
    hotkeyModifiers = settings.hotkey.modifiers
    watermarkLayoutMode = settings.watermark.layoutMode
    watermarkSpacing = settings.watermark.spacing
    watermarkTilePattern = settings.watermark.tilePattern
    watermarkTileRandomness = settings.watermark.tileRandomness
    watermarkTextEnabled = settings.watermark.text.enabled
    watermarkText = settings.watermark.text.text
    watermarkTextColor = settings.watermark.text.color
    watermarkLogoEnabled = settings.watermark.logo.enabled
    watermarkLogoPath = settings.watermark.logo.path
    watermarkLogoBookmarkData = settings.watermark.logo.bookmarkData
    watermarkSize = settings.watermark.logo.size
    watermarkOpacity = settings.watermark.logo.opacity
    watermarkPosition = settings.watermark.logo.positionMode
    cleanupMode = settings.cleanup.mode
    cleanupIncludeSaved = settings.cleanup.includeSavedFiles
    cleanupDurationHours = settings.cleanup.durationSeconds / 3600.0
    saveDirectory = settings.cleanup.saveDirectory
    saveDirectoryBookmarkData = settings.cleanup.saveDirectoryBookmarkData
    queuePanelEnabled = settings.queue.panelEnabled
    captureMode = settings.capture.mode
    captureDelaySeconds = settings.capture.delaySeconds
    lastCaptureRegion = settings.capture.lastRegion
    fullScreenHotkeyEnabled = settings.fullScreenHotkey.enabled
    fullScreenHotkeyKey = settings.fullScreenHotkey.key
    fullScreenHotkeyModifiers = settings.fullScreenHotkey.modifiers
    exportPresetID = settings.export.selectedPresetID
    filenameTemplate = settings.export.filenameTemplate
    defaultQuickAction = settings.export.defaultQuickAction
    galleryOCREnabled = settings.gallery.ocrEnabled
    gallerySearchIndexEnabled = settings.gallery.searchIndexEnabled
    appLanguageCode = settings.localization.appLanguageCode
    textRecognitionLanguageCodes = settings.localization.textRecognitionLanguageCodes
  }
}

private enum SettingsStorage {
  private static let settingsKey = "qpark_shot.app_settings.v2"

  private static let decoder = JSONDecoder()
  private static let encoder = JSONEncoder()

  static func load(defaults: UserDefaults = .standard) -> AppSettings {
    if let settings = decodeSettings(forKey: settingsKey, defaults: defaults) {
      return settings
    }

    return AppSettings()
  }

  static func save(_ settings: AppSettings, defaults: UserDefaults = .standard) {
    guard let data = try? encoder.encode(settings),
          let jsonString = String(data: data, encoding: .utf8) else {
      return
    }

    defaults.set(jsonString, forKey: settingsKey)
  }

  private static func decodeSettings(forKey key: String, defaults: UserDefaults) -> AppSettings? {
    guard let jsonString = defaults.string(forKey: key),
          let data = jsonString.data(using: .utf8) else {
      return nil
    }

    return try? decoder.decode(AppSettings.self, from: data)
  }
}
