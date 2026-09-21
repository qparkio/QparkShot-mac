import Cocoa
import SwiftUI
import UniformTypeIdentifiers

final class PreferencesWindowController: NSObject, NSWindowDelegate {
  static let shared = PreferencesWindowController()

  private var window: NSWindow?
  private let navigation = PreferencesNavigation()

  private override init() {}

  func show(about: Bool = false) {
    let mainWindow = NSApp.windows.first { $0.identifier == MainAppWindow.mainWindowIdentifier }
    if about { navigation.selectedPane = .about }
    let wasVisible = self.window?.isVisible == true
    let window = self.window ?? makeWindow()
    self.window = window
    window.title = localized("common.settings")
    window.makeKeyAndOrderFront(nil)
    if !wasVisible, let mainWindow {
      window.contentView?.layoutSubtreeIfNeeded()
      let visible = mainWindow.screen?.visibleFrame ?? mainWindow.frame
      let origin = NSPoint(
        x: min(max(mainWindow.frame.midX - window.frame.width / 2, visible.minX), max(visible.minX, visible.maxX - window.frame.width)),
        y: min(max(mainWindow.frame.midY - window.frame.height / 2, visible.minY), max(visible.minY, visible.maxY - window.frame.height))
      )
      window.setFrameOrigin(origin)
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  func refreshLocalizedChrome() {
    window?.title = localized("common.settings")
  }

  func windowWillClose(_ notification: Notification) {
    window = nil
  }

  private func makeWindow() -> NSWindow {
    let root = PreferencesRootView(navigation: navigation)
    let controller = NSHostingController(rootView: root)
    controller.sizingOptions = []
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    let initialFrame = window.frame
    window.contentViewController = controller
    window.setFrame(initialFrame, display: false)
    window.contentMinSize = NSSize(width: 780, height: 580)
    if AppTestEnvironment.value("QPARK_TEST_SETTINGS_MIN") == "1" {
      window.setContentSize(NSSize(width: 780, height: 580))
    }
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.center()
    return window
  }
}

private enum PreferencesPane: String, CaseIterable, Identifiable {
  case general
  case capture
  case export
  case watermark
  case storage
  case about

  var id: String { rawValue }

  var titleKey: String {
    switch self {
    case .general: return "settings.general"
    case .capture: return "settings.capture"
    case .export: return "settings.export"
    case .watermark: return "settings.watermark"
    case .about: return "settings.about"
    case .storage: return "settings.storage"
    }
  }

  var subtitleKey: String {
    switch self {
    case .general: return "settings.subtitle.general"
    case .capture: return "settings.subtitle.capture"
    case .export: return "settings.subtitle.export"
    case .watermark: return "settings.subtitle.watermark"
    case .about: return "app.name"
    case .storage: return "settings.subtitle.storage"
    }
  }

  var iconName: String {
    switch self {
    case .general: return "gearshape.fill"
    case .capture: return "camera.viewfinder"
    case .export: return "square.and.arrow.down.fill"
    case .watermark: return "seal.fill"
    case .about: return "info.circle.fill"
    case .storage: return "folder.fill"
    }
  }

  var tint: Color {
    switch self {
    case .general: return .gray
    case .capture: return .blue
    case .export: return .green
    case .watermark: return .orange
    case .about: return .blue
    case .storage: return .purple
    }
  }
}

private final class PreferencesNavigation: ObservableObject {
  @Published var selectedPane: PreferencesPane = .general
}

private struct PreferencesRootView: View {
  @ObservedObject private var store = SettingsStore.shared
  @ObservedObject private var localization = LocalizationController.shared
  @ObservedObject var navigation: PreferencesNavigation
  private var selectedPane: PreferencesPane { navigation.selectedPane }

  var body: some View {
    NavigationSplitView {
      PreferencesSidebar(selectedPane: $navigation.selectedPane)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
    } detail: {
      ScrollView {
        VStack(spacing: 12) {
          SettingsPaneHeader(pane: selectedPane)
          selectedContent
        }
        .padding(20)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity, alignment: .top)
      }
      .navigationTitle(localized(selectedPane.titleKey))
    }
    .frame(minWidth: 780, minHeight: 580)
    .environment(\.locale, localization.locale)
    .environment(\.layoutDirection, localization.layoutDirection)
  }

  @ViewBuilder
  private var selectedContent: some View {
    switch selectedPane {
    case .general:
      general
    case .capture:
      capture
    case .export:
      export
    case .watermark:
      watermark
    case .storage:
      storage
    case .about:
      about
    }
  }

  private var about: some View {
    SettingsCard {
      VStack(spacing: 16) {
        Image(nsImage: NSApplication.shared.applicationIconImage)
          .resizable()
          .frame(width: 80, height: 80)
        Text(localized("app.name")).font(.title.bold())
        Text("\(localized("settings.version")) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"))")
          .foregroundStyle(.secondary)
        Text(Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? "© 2026 QPARK")
        Link("qpark.io", destination: URL(string: "https://qpark.io")!)
        Link("work@qpark.io", destination: URL(string: "mailto:work@qpark.io")!)
      }
      .frame(maxWidth: .infinity)
      .padding(24)
      .textSelection(.enabled)
    }
  }

  private var general: some View {
    VStack(spacing: 12) {
      SettingsCard {
        SettingsRow(titleKey: "settings.language") {
          Picker(localized("settings.language"), selection: languageBinding) {
            ForEach(AppLanguage.allCases) { language in
              Text(language.displayName(in: localization.language))
                .tag(language.rawValue)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 240)
        }

        SettingsDivider()

        SettingsRow(titleKey: "settings.appearance") {
          Picker(localized("settings.appearance"), selection: saveBinding(\.themePreference, change: .appearance)) {
            Text(localized("settings.theme_system")).tag("system")
            Text(localized("settings.theme_light")).tag("light")
            Text(localized("settings.theme_dark")).tag("dark")
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 240)
        }
      }

      SettingsCard {
        SettingsRow(titleKey: "settings.enable_ocr") {
          Toggle("", isOn: saveBinding(\.galleryOCREnabled, change: .library))
            .labelsHidden()
            .toggleStyle(.switch)
        }

        SettingsDivider()

        SettingsRow(titleKey: "settings.search_metadata") {
          Toggle("", isOn: saveBinding(\.gallerySearchIndexEnabled, change: .library))
            .labelsHidden()
            .toggleStyle(.switch)
        }
      }

      SettingsCard {
        VStack(alignment: .leading, spacing: 10) {
          Text(localized("settings.ocr_languages"))
            .font(.body.weight(.semibold))
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(AppLanguage.allCases) { language in
              Toggle(isOn: recognitionBinding(for: language)) {
                Text(language.displayName(in: localization.language))
                  .lineLimit(1)
              }
              .toggleStyle(.checkbox)
            }
          }
        }
        .padding(14)
      }
    }
  }

  private var capture: some View {
    VStack(spacing: 12) {
      SettingsCard {
        SettingsRow(titleKey: "settings.after_capture") {
          Picker(localized("settings.after_capture"), selection: saveBinding(\.defaultQuickAction, change: .capture)) {
            Text(localized("settings.open_editor")).tag("edit")
            Text(localized("settings.show_review")).tag("overlay")
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 250)
        }

        SettingsDivider()

        SettingsRow(titleKey: "settings.capture_mode") {
          Picker(localized("settings.capture_mode"), selection: saveBinding(\.captureMode, change: .capture)) {
            Text(localized("capture.selected_area")).tag("selection")
            Text(localized("capture.full_screen")).tag("fullScreen")
            Text(localized("capture.window")).tag("window")
            Text(localized("capture.repeat_area")).tag("repeatLastArea")
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 250)
        }

        SettingsDivider()

        SettingsRow(titleKey: "settings.capture_delay") {
          Stepper(
            "\(store.captureDelaySeconds)s",
            value: saveBinding(\.captureDelaySeconds, change: .capture),
            in: 0...30
          )
          .frame(width: 120)
        }

        SettingsDivider()

        SettingsRow(titleKey: "settings.queue_panel") {
          Toggle("", isOn: saveBinding(\.queuePanelEnabled, change: .capture))
            .labelsHidden()
            .toggleStyle(.switch)
        }
      }

      SettingsCard {
        SettingsRow(titleKey: "settings.selection_shortcut") {
          HStack(spacing: 10) {
            Toggle("", isOn: saveBinding(\.hotkeyEnabled, change: .shortcuts))
              .labelsHidden()
              .toggleStyle(.switch)
            ShortcutRecorder(
              shortcut: selectionHotkeyBinding,
              otherShortcut: store.fullScreenHotkey,
              identifier: "settings.shortcut.selection"
            )
          }
        }

        SettingsDivider()

        SettingsRow(titleKey: "settings.fullscreen_shortcut") {
          HStack(spacing: 10) {
            Toggle("", isOn: saveBinding(\.fullScreenHotkeyEnabled, change: .shortcuts))
              .labelsHidden()
              .toggleStyle(.switch)
            ShortcutRecorder(
              shortcut: fullScreenHotkeyBinding,
              otherShortcut: store.selectionHotkey,
              identifier: "settings.shortcut.fullScreen"
            )
          }
        }
      }

      if let errorKey = shortcutValidationKey {
        Label(localized(errorKey), systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var export: some View {
    SettingsCard {
      SettingsRow(titleKey: "settings.export_preset") {
        Picker(localized("settings.export_preset"), selection: saveBinding(\.exportPresetID, change: .export)) {
          ForEach(ExportPreset.all) { preset in
            Text(localized("export.preset.\(preset.id)")).tag(preset.id)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 220)
      }

      SettingsDivider()

      SettingsRow(titleKey: "settings.filename_template") {
        TextField(localized("settings.filename_template"), text: saveBinding(\.filenameTemplate, change: .export, debounce: true))
          .textFieldStyle(.roundedBorder)
          .frame(width: 280)
      }
    }
  }

  private var watermark: some View {
    VStack(spacing: 12) {
      WatermarkPreviewPanel()

      SettingsCard {
        SettingsRow(titleKey: "settings.watermark_text") {
          Toggle("", isOn: saveBinding(\.watermarkTextEnabled, change: .watermark))
            .labelsHidden()
            .toggleStyle(.switch)
        }

        SettingsDivider()

        SettingsRow(titleKey: "editor.tool_text") {
          TextField(localized("settings.watermark_text"), text: saveBinding(\.watermarkText, change: .watermark, debounce: true))
            .textFieldStyle(.roundedBorder)
            .frame(width: 260)
            .disabled(!store.watermarkTextEnabled)
        }

        SettingsDivider()

        SettingsRow(titleKey: "editor.color") {
          ColorPicker(
            localized("editor.color"),
            selection: Binding(
              get: { Color(hexString: store.watermarkTextColor) },
              set: {
                store.watermarkTextColor = hexString(from: $0)
                store.save(change: .watermark, debounce: true)
              }
            )
          )
          .labelsHidden()
          .disabled(!store.watermarkTextEnabled)
        }
      }

      SettingsCard {
        SettingsRow(titleKey: "settings.watermark_layout") {
          Picker(localized("settings.watermark_layout"), selection: saveBinding(\.watermarkLayoutMode, change: .watermark)) {
            Text(localized("settings.watermark_layout_single")).tag("single")
            Text(localized("settings.watermark_layout_tiled")).tag("tiled")
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 220)
        }

        SettingsDivider()

        SettingsRow(titleKey: "settings.watermark_position") {
          Picker(localized("settings.watermark_position"), selection: saveBinding(\.watermarkPosition, change: .watermark)) {
            Text(localized("settings.position.bottom_right")).tag("bottomRight")
            Text(localized("settings.position.bottom_left")).tag("bottomLeft")
            Text(localized("settings.position.top_right")).tag("topRight")
            Text(localized("settings.position.top_left")).tag("topLeft")
            Text(localized("settings.position.center")).tag("center")
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 220)
        }

        SettingsDivider()

        SettingsRow(titleKey: "settings.watermark_spacing") {
          HStack(spacing: 10) {
            Slider(value: saveBinding(\.watermarkSpacing, change: .watermark, debounce: true), in: 72...320)
              .frame(width: 180)
            Text("\(Int(store.watermarkSpacing))")
              .font(.caption.monospacedDigit())
              .foregroundColor(.secondary)
              .frame(width: 38, alignment: .trailing)
          }
        }
        .disabled(store.watermarkLayoutMode != "tiled")

        SettingsDivider()

        SettingsRow(titleKey: "settings.watermark_tile_pattern") {
          Picker(localized("settings.watermark_tile_pattern"), selection: saveBinding(\.watermarkTilePattern, change: .watermark)) {
            Text(localized("settings.tile.aligned")).tag("aligned")
            Text(localized("settings.tile.brick")).tag("brick")
            Text(localized("settings.tile.random")).tag("random")
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 220)
        }
        .disabled(store.watermarkLayoutMode != "tiled")

        SettingsDivider()

        SettingsRow(titleKey: "settings.watermark_tile_randomness") {
          HStack(spacing: 10) {
            Slider(value: saveBinding(\.watermarkTileRandomness, change: .watermark, debounce: true), in: 0...1)
              .frame(width: 180)
            Text("\(Int(store.watermarkTileRandomness * 100))%")
              .font(.caption.monospacedDigit())
              .foregroundColor(.secondary)
              .frame(width: 42, alignment: .trailing)
          }
        }
        .disabled(store.watermarkLayoutMode != "tiled" || store.watermarkTilePattern != "random")
      }

      SettingsCard {
        SettingsRow(titleKey: "settings.watermark_logo") {
          Toggle("", isOn: saveBinding(\.watermarkLogoEnabled, change: .watermark))
            .labelsHidden()
            .toggleStyle(.switch)
        }

        SettingsDivider()

        SettingsRow(titleKey: "settings.logo_file") {
          HStack(spacing: 8) {
            Text(store.watermarkLogoPath.isEmpty ? localized("settings.no_logo") : URL(fileURLWithPath: store.watermarkLogoPath).lastPathComponent)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
              .frame(width: 130, alignment: .trailing)
            Button(localized("settings.choose_logo"), action: chooseLogo)
            Button(localized("common.clear")) {
              store.watermarkLogoPath = ""
              store.watermarkLogoBookmarkData = nil
              store.save(change: .watermark)
            }
            .disabled(store.watermarkLogoPath.isEmpty)
          }
        }

        SettingsDivider()

        SettingsRow(titleKey: "settings.opacity") {
          HStack(spacing: 10) {
            Slider(value: saveBinding(\.watermarkOpacity, change: .watermark, debounce: true), in: 0...1)
              .frame(width: 180)
            Text("\(Int(store.watermarkOpacity * 100))%")
              .font(.caption.monospacedDigit())
              .foregroundColor(.secondary)
              .frame(width: 42, alignment: .trailing)
          }
        }

        SettingsDivider()

        SettingsRow(titleKey: "settings.size") {
          HStack(spacing: 10) {
            Slider(value: saveBinding(\.watermarkSize, change: .watermark, debounce: true), in: 32...420)
              .frame(width: 180)
            Text("\(Int(store.watermarkSize))")
              .font(.caption.monospacedDigit())
              .foregroundColor(.secondary)
              .frame(width: 38, alignment: .trailing)
          }
        }
      }
    }
  }

  private var storage: some View {
    SettingsCard {
      SettingsRow(titleKey: "settings.save_location") {
        HStack(spacing: 10) {
          Text(store.saveDirectory.isEmpty ? localized("settings.default_pictures") : store.saveDirectory)
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 210, alignment: .trailing)
          Button(localized("settings.choose_folder"), action: chooseFolder)
          Button(localized("common.clear")) {
            store.saveDirectory = ""
            store.saveDirectoryBookmarkData = nil
            store.save(change: .cleanup)
            WorkspaceStore.shared.loadLibrary()
          }
          .disabled(store.saveDirectory.isEmpty)
        }
      }

      SettingsDivider()

      SettingsRow(titleKey: "settings.cleanup") {
        Picker(localized("settings.cleanup"), selection: saveBinding(\.cleanupMode, change: .cleanup)) {
          Text(localized("settings.cleanup_never")).tag("never")
          Text(localized("settings.cleanup_duration")).tag("afterDuration")
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 190)
      }

      SettingsDivider()

      SettingsRow(titleKey: "settings.cleanup_age") {
        Picker(localized("settings.cleanup_age"), selection: saveBinding(\.cleanupDurationHours, change: .cleanup)) {
          ForEach([1.0, 6.0, 12.0, 24.0, 168.0, 720.0], id: \.self) { hours in
            Text(cleanupDurationLabel(hours: hours)).tag(hours)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 190)
      }
      .disabled(store.cleanupMode == CleanupMode.never.rawValue)

      SettingsDivider()

      SettingsRow(titleKey: "settings.cleanup_saved") {
        Toggle("", isOn: saveBinding(\.cleanupIncludeSaved, change: .cleanup))
          .labelsHidden()
          .toggleStyle(.switch)
      }
      .disabled(store.cleanupMode == CleanupMode.never.rawValue)
    }
  }

  private var languageBinding: Binding<String> {
    Binding(
      get: { store.appLanguageCode },
      set: { code in
        store.appLanguageCode = code
        store.save(change: .localization)
      }
    )
  }

  private func recognitionBinding(for language: AppLanguage) -> Binding<Bool> {
    Binding(
      get: { store.textRecognitionLanguageCodes.contains(language.rawValue) },
      set: { enabled in
        var codes = store.textRecognitionLanguageCodes
        if enabled {
          if !codes.contains(language.rawValue) {
            codes.append(language.rawValue)
          }
        } else {
          codes.removeAll { $0 == language.rawValue }
        }
        if codes.isEmpty {
          codes = [AppLanguage.english.rawValue]
        }
        store.textRecognitionLanguageCodes = codes
        store.save(change: .library)
      }
    )
  }

  private func saveBinding<Value>(
    _ keyPath: ReferenceWritableKeyPath<SettingsStore, Value>,
    change: SettingsChange,
    debounce: Bool = false
  ) -> Binding<Value> {
    Binding(
      get: { store[keyPath: keyPath] },
      set: { value in
        store[keyPath: keyPath] = value
        store.save(change: change, debounce: debounce)
      }
    )
  }

  private var selectionHotkeyBinding: Binding<HotkeySettings> {
    Binding(
      get: { store.selectionHotkey },
      set: { value in
        store.hotkeyKey = value.normalizedKey
        store.hotkeyModifiers = value.normalizedModifiers
        store.save(change: .shortcuts)
      }
    )
  }

  private var shortcutValidationKey: String? {
    let selectionError = store.selectionHotkey.validationError(comparedWith: store.fullScreenHotkey)
    let fullScreenError = store.fullScreenHotkey.validationError(comparedWith: store.selectionHotkey)
    if selectionError == .duplicate || fullScreenError == .duplicate {
      return "settings.shortcut_duplicate"
    }
    if selectionError != nil || fullScreenError != nil {
      return "settings.shortcut_invalid"
    }
    return nil
  }

  private var fullScreenHotkeyBinding: Binding<HotkeySettings> {
    Binding(
      get: { store.fullScreenHotkey },
      set: { value in
        store.fullScreenHotkeyKey = value.normalizedKey
        store.fullScreenHotkeyModifiers = value.normalizedModifiers
        store.save(change: .shortcuts)
      }
    )
  }

  private func cleanupDurationLabel(hours: Double) -> String {
    let formatter = DateComponentsFormatter()
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = localization.locale
    formatter.calendar = calendar
    formatter.unitsStyle = .full
    formatter.maximumUnitCount = 1
    formatter.allowedUnits = hours >= 24 ? [.day] : [.hour]
    return formatter.string(from: hours * 3600) ?? "\(Int(hours)) h"
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = localized("common.open")
    if panel.runModal() == .OK, let url = panel.url {
      store.saveDirectory = url.path
      store.saveDirectoryBookmarkData = try? url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      store.save(change: .cleanup)
      WorkspaceStore.shared.loadLibrary()
    }
  }

  private func chooseLogo() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif]
    panel.prompt = localized("common.open")
    if panel.runModal() == .OK, let url = panel.url {
      store.watermarkLogoPath = url.path
      store.watermarkLogoBookmarkData = try? url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      store.watermarkLogoEnabled = true
      store.save(change: .watermark)
    }
  }
}

private struct PreferencesSidebar: View {
  @Binding var selectedPane: PreferencesPane

  var body: some View {
    List(selection: $selectedPane) {
      ForEach(PreferencesPane.allCases) { pane in
        Label(localized(pane.titleKey), systemImage: pane.iconName)
          .symbolRenderingMode(.hierarchical)
          .accessibilityIdentifier("settings.\(pane.rawValue)")
          .tag(pane)
      }
    }
    .listStyle(.sidebar)
    .navigationTitle(localized("common.settings"))
  }
}

private struct SettingsPaneHeader: View {
  let pane: PreferencesPane

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(localized(pane.titleKey))
        .font(.title2.weight(.semibold))

      Text(localized(pane.subtitleKey))
        .font(.body)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 4)
  }
}

private struct SettingsCard<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) {
      content
    }
    .background(SettingsCardBackground())
  }
}

private struct SettingsCardBackground: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(Color.primary.opacity(0.045))
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(Color.primary.opacity(0.11), lineWidth: 1)
      )
  }
}

private struct SettingsRow<Control: View>: View {
  let titleKey: String
  let subtitleKey: String?
  @ViewBuilder let control: Control

  init(
    titleKey: String,
    subtitleKey: String? = nil,
    @ViewBuilder control: () -> Control
  ) {
    self.titleKey = titleKey
    self.subtitleKey = subtitleKey
    self.control = control()
  }

  private var title: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(localized(titleKey)).font(.body.weight(.medium))
      if let subtitleKey { Text(localized(subtitleKey)).font(.caption).foregroundColor(.secondary) }
    }
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        title.fixedSize(horizontal: true, vertical: false)
        Spacer(minLength: 12)
        control
      }
      VStack(alignment: .leading, spacing: 8) {
        title
        control
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(minHeight: 44)
  }
}

private struct SettingsDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, 14)
  }
}

private struct WatermarkPreviewPanel: View {
  @ObservedObject private var store = SettingsStore.shared
  @State private var previewImage: NSImage?
  @State private var requestID = UUID()

  private var signature: String {
    [
      store.watermarkTextEnabled.description,
      store.watermarkText,
      store.watermarkTextColor,
      store.watermarkLogoEnabled.description,
      store.watermarkLogoPath,
      String(store.watermarkOpacity),
      String(store.watermarkSize),
      store.watermarkPosition,
      store.watermarkLayoutMode,
      String(store.watermarkSpacing),
      store.watermarkTilePattern,
      String(store.watermarkTileRandomness)
    ].joined(separator: "|")
  }

  var body: some View {
    SettingsCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(localized("common.preview"))
            .font(.body.weight(.semibold))
          Spacer()
          Text(localized("settings.watermark_preview_hint"))
            .font(.caption2)
            .foregroundColor(.secondary)
        }

        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(0.82))
          if let previewImage {
            Image(nsImage: previewImage)
              .resizable()
              .interpolation(.high)
              .aspectRatio(contentMode: .fit)
              .padding(10)
          } else {
            ProgressView()
          }
        }
        .frame(height: 255)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .padding(14)
    }
    .onAppear(perform: renderPreview)
    .onChange(of: signature) {
      renderPreview()
    }
  }

  private func renderPreview() {
    let nextRequestID = UUID()
    requestID = nextRequestID
    let watermark = WatermarkRenderSettings.current()
    let baseImage = makeWatermarkPreviewBaseImage()

    DispatchQueue.global(qos: .userInitiated).async {
      let rendered = ExportService.shared.render(
        ExportContext(
          image: baseImage,
          annotations: [],
          cropRect: nil,
          preset: .watermarked,
          watermark: watermark
        )
      )
      DispatchQueue.main.async {
        guard requestID == nextRequestID else { return }
        previewImage = rendered
      }
    }
  }
}

private func makeWatermarkPreviewBaseImage() -> NSImage {
  let size = NSSize(width: 960, height: 540)
  let image = NSImage(size: size)
  image.lockFocus()
  defer { image.unlockFocus() }

  NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.10, alpha: 1).setFill()
  NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

  NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.17, alpha: 1).setFill()
  NSBezierPath(roundedRect: NSRect(x: 42, y: 64, width: 876, height: 412), xRadius: 18, yRadius: 18).fill()

  NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.23, alpha: 1).setFill()
  NSBezierPath(roundedRect: NSRect(x: 42, y: 422, width: 876, height: 54), xRadius: 18, yRadius: 18).fill()

  NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1).setFill()
  NSBezierPath(roundedRect: NSRect(x: 70, y: 92, width: 190, height: 302), xRadius: 12, yRadius: 12).fill()

  for index in 0..<5 {
    let y = 342 - CGFloat(index * 48)
    NSColor(calibratedRed: 0.28, green: 0.30, blue: 0.34, alpha: index == 1 ? 0.90 : 0.48).setFill()
    NSBezierPath(roundedRect: NSRect(x: 92, y: y, width: 132, height: 22), xRadius: 5, yRadius: 5).fill()
  }

  NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1).setFill()
  NSBezierPath(roundedRect: NSRect(x: 292, y: 92, width: 590, height: 302), xRadius: 14, yRadius: 14).fill()

  for index in 0..<4 {
    let width = CGFloat([430, 520, 360, 480][index])
    let y = 330 - CGFloat(index * 54)
    NSColor(calibratedRed: 0.24, green: 0.26, blue: 0.30, alpha: 0.82).setFill()
    NSBezierPath(roundedRect: NSRect(x: 328, y: y, width: width, height: 26), xRadius: 6, yRadius: 6).fill()
    NSColor(calibratedRed: 0.35, green: 0.38, blue: 0.44, alpha: 0.50).setFill()
    NSBezierPath(roundedRect: NSRect(x: 328, y: y - 22, width: width * 0.72, height: 10), xRadius: 4, yRadius: 4).fill()
  }

  NSColor(calibratedRed: 0.06, green: 0.46, blue: 0.92, alpha: 0.85).setFill()
  NSBezierPath(roundedRect: NSRect(x: 328, y: 128, width: 132, height: 34), xRadius: 8, yRadius: 8).fill()

  return image
}

#if DEBUG
private struct PreferencesSurfacePreviews: PreviewProvider {
  static var previews: some View {
    Group {
      PreferencesRootView(navigation: PreferencesNavigation())
        .frame(width: 920, height: 620)
        .preferredColorScheme(.light)
        .environment(\.locale, AppLanguage.german.locale)
        .previewDisplayName("Settings · DE · Light · 920×620")

      PreferencesRootView(navigation: PreferencesNavigation())
        .frame(width: 1280, height: 800)
        .preferredColorScheme(.dark)
        .environment(\.locale, AppLanguage.arabic.locale)
        .environment(\.layoutDirection, LayoutDirection.rightToLeft)
        .previewDisplayName("Settings · Arabic RTL · Dark · 1280×800")
    }
  }
}
#endif
