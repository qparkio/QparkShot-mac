import Foundation

struct AppSettings: Codable, Equatable {
  var themePreference: String
  var hotkey: HotkeySettings
  var watermark: WatermarkSettings
  var cleanup: CleanupSettings
  var queue: QueueSettings
  var capture: CaptureSettings
  var fullScreenHotkey: HotkeySettings
  var export: ExportSettings
  var gallery: GallerySettings
  var localization: LocalizationSettings

  init(
    themePreference: String = "system",
    hotkey: HotkeySettings = HotkeySettings(enabled: true, key: "C", modifiers: ["command", "shift"]),
    watermark: WatermarkSettings = WatermarkSettings(),
    cleanup: CleanupSettings = CleanupSettings(),
    queue: QueueSettings = QueueSettings(),
    capture: CaptureSettings = CaptureSettings(),
    fullScreenHotkey: HotkeySettings = HotkeySettings(enabled: false, key: "F", modifiers: ["command", "shift"]),
    export: ExportSettings = ExportSettings(),
    gallery: GallerySettings = GallerySettings(),
    localization: LocalizationSettings = LocalizationSettings()
  ) {
    self.themePreference = themePreference
    self.hotkey = hotkey
    self.watermark = watermark
    self.cleanup = cleanup
    self.queue = queue
    self.capture = capture
    self.fullScreenHotkey = fullScreenHotkey
    self.export = export
    self.gallery = gallery
    self.localization = localization
  }

  init(from decoder: Decoder) throws {
    let defaults = AppSettings()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    themePreference = try container.decodeIfPresent(String.self, forKey: .themePreference) ?? defaults.themePreference
    hotkey = try container.decodeIfPresent(HotkeySettings.self, forKey: .hotkey) ?? defaults.hotkey
    watermark = try container.decodeIfPresent(WatermarkSettings.self, forKey: .watermark) ?? defaults.watermark
    cleanup = try container.decodeIfPresent(CleanupSettings.self, forKey: .cleanup) ?? defaults.cleanup
    queue = try container.decodeIfPresent(QueueSettings.self, forKey: .queue) ?? defaults.queue
    capture = try container.decodeIfPresent(CaptureSettings.self, forKey: .capture) ?? defaults.capture
    fullScreenHotkey = try container.decodeIfPresent(HotkeySettings.self, forKey: .fullScreenHotkey) ?? defaults.fullScreenHotkey
    export = try container.decodeIfPresent(ExportSettings.self, forKey: .export) ?? defaults.export
    gallery = try container.decodeIfPresent(GallerySettings.self, forKey: .gallery) ?? defaults.gallery
    localization = try container.decodeIfPresent(LocalizationSettings.self, forKey: .localization) ?? defaults.localization
  }
}

struct HotkeySettings: Codable, Equatable {
  var enabled: Bool
  var key: String
  var modifiers: [String]

  init(enabled: Bool, key: String, modifiers: [String]) {
    self.enabled = enabled
    self.key = key
    self.modifiers = modifiers
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    key = try container.decodeIfPresent(String.self, forKey: .key) ?? "C"
    modifiers = try container.decodeIfPresent([String].self, forKey: .modifiers) ?? ["command", "shift"]
  }
}

enum HotkeyValidationError: Equatable {
  case unsupportedKey
  case missingPrimaryModifier
  case duplicate
}

extension HotkeySettings {
  var normalizedKey: String {
    key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
  }

  var normalizedModifiers: [String] {
    let order = ["control", "option", "shift", "command"]
    let normalized = Set(modifiers.map { value -> String in
      switch value.lowercased() {
      case "ctrl": return "control"
      case "alt": return "option"
      default: return value.lowercased()
      }
    })
    return order.filter(normalized.contains)
  }

  func validationError(comparedWith other: HotkeySettings? = nil) -> HotkeyValidationError? {
    guard normalizedKey.count == 1,
          normalizedKey.range(of: "^[A-Z0-9]$", options: .regularExpression) != nil else {
      return .unsupportedKey
    }

    let primaryModifiers = Set(["command", "control", "option"])
    guard !primaryModifiers.isDisjoint(with: normalizedModifiers) else {
      return .missingPrimaryModifier
    }

    if enabled,
       let other,
       other.enabled,
       normalizedKey == other.normalizedKey,
       normalizedModifiers == other.normalizedModifiers {
      return .duplicate
    }

    return nil
  }
}

struct WatermarkSettings: Codable, Equatable {
  var layoutMode: String
  var spacing: Double
  var tilePattern: String
  var tileRandomness: Double
  var text: WatermarkTextSettings
  var logo: WatermarkLogoSettings

  init(
    layoutMode: String = "single",
    spacing: Double = 150.0,
    tilePattern: String = "aligned",
    tileRandomness: Double = 0.45,
    text: WatermarkTextSettings = WatermarkTextSettings(),
    logo: WatermarkLogoSettings = WatermarkLogoSettings()
  ) {
    self.layoutMode = layoutMode
    self.spacing = spacing
    self.tilePattern = tilePattern
    self.tileRandomness = tileRandomness
    self.text = text
    self.logo = logo
  }

  init(from decoder: Decoder) throws {
    let defaults = WatermarkSettings()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    layoutMode = try container.decodeIfPresent(String.self, forKey: .layoutMode) ?? defaults.layoutMode
    spacing = try container.decodeIfPresent(Double.self, forKey: .spacing) ?? defaults.spacing
    tilePattern = try container.decodeIfPresent(String.self, forKey: .tilePattern) ?? defaults.tilePattern
    tileRandomness = try container.decodeIfPresent(Double.self, forKey: .tileRandomness) ?? defaults.tileRandomness
    text = try container.decodeIfPresent(WatermarkTextSettings.self, forKey: .text) ?? defaults.text
    logo = try container.decodeIfPresent(WatermarkLogoSettings.self, forKey: .logo) ?? defaults.logo
  }
}

struct WatermarkTextSettings: Codable, Equatable {
  var enabled: Bool
  var text: String
  var color: String

  init(enabled: Bool = false, text: String = "QPARK Shot", color: String = "#FFFFFF") {
    self.enabled = enabled
    self.text = text
    self.color = color
  }

  init(from decoder: Decoder) throws {
    let defaults = WatermarkTextSettings()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
    text = try container.decodeIfPresent(String.self, forKey: .text) ?? defaults.text
    color = try container.decodeIfPresent(String.self, forKey: .color) ?? defaults.color
  }
}

struct WatermarkLogoSettings: Codable, Equatable {
  var enabled: Bool
  var path: String
  var bookmarkData: Data?
  var size: Double
  var opacity: Double
  var positionMode: String

  init(
    enabled: Bool = false,
    path: String = "",
    bookmarkData: Data? = nil,
    size: Double = 120.0,
    opacity: Double = 0.5,
    positionMode: String = "bottomRight"
  ) {
    self.enabled = enabled
    self.path = path
    self.bookmarkData = bookmarkData
    self.size = size
    self.opacity = opacity
    self.positionMode = positionMode
  }

  init(from decoder: Decoder) throws {
    let defaults = WatermarkLogoSettings()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
    path = try container.decodeIfPresent(String.self, forKey: .path) ?? defaults.path
    bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData) ?? defaults.bookmarkData
    size = try container.decodeIfPresent(Double.self, forKey: .size) ?? defaults.size
    opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? defaults.opacity
    positionMode = try container.decodeIfPresent(String.self, forKey: .positionMode) ?? defaults.positionMode
  }
}

struct CleanupSettings: Codable, Equatable {
  var mode: String
  var includeSavedFiles: Bool
  var durationSeconds: Double
  var saveDirectory: String
  var saveDirectoryBookmarkData: Data?

  init(
    mode: String = "never",
    includeSavedFiles: Bool = false,
    durationSeconds: Double = 86_400,
    saveDirectory: String = "",
    saveDirectoryBookmarkData: Data? = nil
  ) {
    self.mode = mode
    self.includeSavedFiles = includeSavedFiles
    self.durationSeconds = durationSeconds
    self.saveDirectory = saveDirectory
    self.saveDirectoryBookmarkData = saveDirectoryBookmarkData
  }

  init(from decoder: Decoder) throws {
    let defaults = CleanupSettings()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? defaults.mode
    includeSavedFiles = try container.decodeIfPresent(Bool.self, forKey: .includeSavedFiles) ?? defaults.includeSavedFiles
    durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? defaults.durationSeconds
    saveDirectory = try container.decodeIfPresent(String.self, forKey: .saveDirectory) ?? defaults.saveDirectory
    saveDirectoryBookmarkData = try container.decodeIfPresent(Data.self, forKey: .saveDirectoryBookmarkData) ?? defaults.saveDirectoryBookmarkData
  }
}

enum CleanupMode: String, CaseIterable, Codable {
  case never
  case afterDuration
}

struct CleanupPolicy: Equatable {
  var mode: CleanupMode
  var maxAge: TimeInterval
  var includeSavedFiles: Bool

  static let disabled = CleanupPolicy(
    mode: .never,
    maxAge: 86_400,
    includeSavedFiles: false
  )
}

struct CleanupReport: Equatable {
  var deletedTemporaryPaths: [String] = []
  var trashedSavedPaths: [String] = []
  var failures: [String] = []

  var changedAnything: Bool {
    !deletedTemporaryPaths.isEmpty || !trashedSavedPaths.isEmpty
  }
}

struct QueueSettings: Codable, Equatable {
  var panelEnabled: Bool

  init(panelEnabled: Bool = true) {
    self.panelEnabled = panelEnabled
  }
}

struct CaptureSettings: Codable, Equatable {
  var mode: String
  var delaySeconds: Int
  var lastRegion: CaptureRegion?

  init(mode: String = "selection", delaySeconds: Int = 0, lastRegion: CaptureRegion? = nil) {
    self.mode = mode
    self.delaySeconds = delaySeconds
    self.lastRegion = lastRegion
  }

  init(from decoder: Decoder) throws {
    let defaults = CaptureSettings()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? defaults.mode
    delaySeconds = try container.decodeFlexibleIntIfPresent(forKey: .delaySeconds) ?? defaults.delaySeconds
    lastRegion = try container.decodeIfPresent(CaptureRegion.self, forKey: .lastRegion)
  }
}

struct ExportSettings: Codable, Equatable {
  var selectedPresetID: String
  var filenameTemplate: String
  var defaultQuickAction: String

  init(
    selectedPresetID: String = ExportPreset.watermarked.id,
    filenameTemplate: String = "{date}_{time}_{preset}",
    defaultQuickAction: String = "edit"
  ) {
    self.selectedPresetID = selectedPresetID
    self.filenameTemplate = filenameTemplate
    self.defaultQuickAction = defaultQuickAction
  }

  init(from decoder: Decoder) throws {
    let defaults = ExportSettings()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    selectedPresetID = try container.decodeIfPresent(String.self, forKey: .selectedPresetID) ?? defaults.selectedPresetID
    filenameTemplate = try container.decodeIfPresent(String.self, forKey: .filenameTemplate) ?? defaults.filenameTemplate
    defaultQuickAction = try container.decodeIfPresent(String.self, forKey: .defaultQuickAction) ?? defaults.defaultQuickAction
  }
}

struct GallerySettings: Codable, Equatable {
  var ocrEnabled: Bool
  var searchIndexEnabled: Bool

  init(ocrEnabled: Bool = true, searchIndexEnabled: Bool = true) {
    self.ocrEnabled = ocrEnabled
    self.searchIndexEnabled = searchIndexEnabled
  }
}

private extension KeyedDecodingContainer {
  func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
    if let value = try decodeIfPresent(Int.self, forKey: key) {
      return value
    }
    if let value = try decodeIfPresent(Double.self, forKey: key) {
      return Int(value)
    }
    return nil
  }
}
