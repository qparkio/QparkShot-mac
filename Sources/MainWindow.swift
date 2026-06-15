import Cocoa
import SwiftUI
import Combine
import ImageIO

enum MainWindowDestination: Equatable {
  case gallery
  case settings
  case editor(String)
}

final class MainWindowNavigation: ObservableObject {
  static let shared = MainWindowNavigation()
  
  @Published private(set) var destination: MainWindowDestination = .gallery
  
  private init() {}
  
  func showGallery() {
    destination = .gallery
  }
  
  func showSettings() {
    SettingsStore.shared.load()
    destination = .settings
  }
  
  func openEditor(_ imagePath: String) {
    destination = .editor(imagePath)
  }
}

class MainAppWindow: NSWindow {
  static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("QPARKShotMainWindow")

  private var didInstallRootContent = false

  func installRootContent() {
    guard !didInstallRootContent else { return }
    didInstallRootContent = true
    
    identifier = Self.mainWindowIdentifier
    isReleasedWhenClosed = false
    
    let contentView = MainWindowView(navigation: MainWindowNavigation.shared)
    let hostingController = NSHostingController(rootView: contentView)
    
    let windowFrame = self.frame
    self.contentViewController = hostingController
    self.setFrame(windowFrame, display: true)
    self.title = "QPARK Shot"

    // Enable native macOS vibrancy (frosted glass) effect
    self.titlebarAppearsTransparent = false
    self.titleVisibility = .visible
    if self.styleMask.contains(.fullSizeContentView) {
      self.styleMask.remove(.fullSizeContentView)
    }
    self.isOpaque = false
    self.backgroundColor = .clear

    let visualEffectView = NSVisualEffectView()
    visualEffectView.translatesAutoresizingMaskIntoConstraints = false
    visualEffectView.material = .underWindowBackground
    visualEffectView.state = .active
    visualEffectView.blendingMode = .behindWindow

    if let windowContentView = self.contentView {
      windowContentView.addSubview(visualEffectView, positioned: .below, relativeTo: hostingController.view)
      NSLayoutConstraint.activate([
        visualEffectView.leadingAnchor.constraint(equalTo: windowContentView.leadingAnchor),
        visualEffectView.trailingAnchor.constraint(equalTo: windowContentView.trailingAnchor),
        visualEffectView.topAnchor.constraint(equalTo: windowContentView.topAnchor),
        visualEffectView.bottomAnchor.constraint(equalTo: windowContentView.bottomAnchor),
      ])
    }
  }
}

struct MainWindowView: View {
  @ObservedObject var navigation: MainWindowNavigation
  @ObservedObject private var store = SettingsStore.shared
  
  var body: some View {
    content
      .preferredColorScheme(store.preferredColorScheme)
  }
  
  @ViewBuilder
  private var content: some View {
    switch navigation.destination {
    case .gallery:
      MainGalleryView()
    case .settings:
      SettingsView(store: SettingsStore.shared) {
        navigation.showGallery()
      }
    case .editor(let imagePath):
      EditorView(
        imagePath: imagePath,
        onClose: {
          navigation.showGallery()
        },
        onSave: {
          DispatchQueue.main.async {
            NotificationCenter.default.post(
              name: NSNotification.Name("ReloadGalleryNotification"),
              object: nil
            )
            navigation.showGallery()
          }
        }
      )
    }
  }
}

// MARK: - Main Gallery View
struct MainGalleryView: View {
  @State private var recentScreenshots: [String] = []
  @State private var thumbnails: [String: NSImage] = [:]
  @State private var pendingThumbnails: Set<String> = []
  @State private var loadRequestID = UUID()
  @State private var isBusy = false
  
  let reloadPublisher = NotificationCenter.default.publisher(for: NSNotification.Name("ReloadGalleryNotification"))
  
  var body: some View {
    VStack(spacing: 0) {
      // Gallery Toolbar
      HStack {
        Spacer()
        
        Button(action: {
          AppDelegate.shared.triggerCaptureFlow()
        }) {
          Label("Capture", systemImage: "camera.viewfinder")
            .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .disabled(isBusy)
        
        Button(action: {
          AppDelegate.shared.showSettings()
        }) {
          Label("Preferences", systemImage: "gearshape")
            .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .help("Preferences")
        
        Button(action: {
          clearCache()
        }) {
          Image(systemName: "trash")
            .font(.system(size: 12))
        }
        .buttonStyle(.bordered)
        .help("Clear Cache")
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(Color.clear)
      
      Divider()
      
      // Screenshots Grid
      if recentScreenshots.isEmpty {
        VStack(spacing: 12) {
          Image(systemName: "photo.on.rectangle.angled")
            .font(.system(size: 40))
            .foregroundColor(.secondary)
          Text("No screenshots found.")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 14)], spacing: 14) {
            ForEach(recentScreenshots, id: \.self) { path in
              ScreenshotGridItem(
                path: path,
                thumbnail: thumbnails[path],
                onLoad: { loadThumbnailIfNeeded(path: path) },
                onOpen: { AppDelegate.shared.openEditor(for: path) },
                onCopy: { copyToClipboard(path: path) },
                onShare: { shareImage(path: path) },
                onDelete: { deleteImage(path: path) }
              )
            }
          }
          .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    .onAppear {
      loadRecent()
      performCleanup()
    }
    .onReceive(reloadPublisher) { _ in
      loadRecent()
    }
  }
  
  private func loadRecent() {
    let requestID = UUID()
    loadRequestID = requestID
    let fileManager = FileManager.default
    let saveDirectory = SettingsStore.shared.saveDirectory
    
    DispatchQueue.global(qos: .userInitiated).async {
      var folderURL = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first!.appendingPathComponent("QPARK Shot")
      
      if !saveDirectory.isEmpty {
        folderURL = URL(fileURLWithPath: saveDirectory)
      }
      
      var allPaths: [String] = []
      
      if let contents = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) {
        allPaths.append(contentsOf: contents.filter { $0.pathExtension.lowercased() == "png" }.map { $0.path })
      }
      
      let tempFolder = fileManager.temporaryDirectory.appendingPathComponent("QPARK Shot")
      if let tempContents = try? fileManager.contentsOfDirectory(at: tempFolder, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) {
        allPaths.append(contentsOf: tempContents.filter { $0.pathExtension.lowercased() == "png" }.map { $0.path })
      }
      
      let sortedPaths = allPaths.sorted { path1, path2 in
        let d1 = (try? URL(fileURLWithPath: path1).resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
        let d2 = (try? URL(fileURLWithPath: path2).resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
        return d1 > d2
      }
      
      DispatchQueue.main.async {
        guard loadRequestID == requestID else { return }
        let validPaths = Set(sortedPaths)
        recentScreenshots = sortedPaths
        thumbnails = thumbnails.filter { validPaths.contains($0.key) }
        pendingThumbnails = pendingThumbnails.filter { validPaths.contains($0) }
      }
    }
  }
  
  private func loadThumbnailIfNeeded(path: String) {
    guard thumbnails[path] == nil, !pendingThumbnails.contains(path) else { return }
    pendingThumbnails.insert(path)
    
    DispatchQueue.global(qos: .utility).async {
      let thumbnail = makeThumbnailImage(path: path, maxPixelSize: 360)
      DispatchQueue.main.async {
        pendingThumbnails.remove(path)
        guard recentScreenshots.contains(path) else { return }
        if let thumbnail {
          thumbnails[path] = thumbnail
        }
      }
    }
  }
  
  private func deleteImage(path: String) {
    try? FileManager.default.removeItem(atPath: path)
    thumbnails.removeValue(forKey: path)
    pendingThumbnails.remove(path)
    loadRecent()
  }
  
  private func clearCache() {
    let fileManager = FileManager.default
    let tempFolder = fileManager.temporaryDirectory.appendingPathComponent("QPARK Shot")
    let contents = (try? fileManager.contentsOfDirectory(at: tempFolder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
    for fileURL in contents {
      try? fileManager.removeItem(at: fileURL)
    }
    thumbnails.removeAll()
    pendingThumbnails.removeAll()
    loadRecent()
  }
  
  private func copyToClipboard(path: String) {
    guard !isBusy else { return }
    isBusy = true
    
    DispatchQueue.global(qos: .userInitiated).async {
      let image = loadImageForRendering(path: path)
      DispatchQueue.main.async {
        isBusy = false
        guard let image else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
      }
    }
  }
  
  private func shareImage(path: String) {
    let url = URL(fileURLWithPath: path)
    let picker = NSSharingServicePicker(items: [url])
    DispatchQueue.main.async {
      if let window = NSApp.keyWindow, let contentView = window.contentView {
        let rect = NSRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
        picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
      }
    }
  }
  
  private func performCleanup() {
    let store = SettingsStore.shared
    guard store.cleanupMode == "afterDuration" else { return }
    
    let cleanupIncludeSaved = store.cleanupIncludeSaved
    let cleanupDurationHours = store.cleanupDurationHours
    let saveDirectory = store.saveDirectory
    
    DispatchQueue.global(qos: .utility).async {
      let limitDate = Date().addingTimeInterval(-cleanupDurationHours * 3600.0)
      let fileManager = FileManager.default
      
      if cleanupIncludeSaved {
        var folderURL = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first!.appendingPathComponent("QPARK Shot")
        if !saveDirectory.isEmpty {
          folderURL = URL(fileURLWithPath: saveDirectory)
        }
        
        let contents = (try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)) ?? []
        for fileURL in contents {
          if let creationDate = try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
             creationDate < limitDate {
            try? fileManager.removeItem(at: fileURL)
          }
        }
      }
      
      let tempFolder = fileManager.temporaryDirectory.appendingPathComponent("QPARK Shot")
      let tempContents = (try? fileManager.contentsOfDirectory(at: tempFolder, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)) ?? []
      for fileURL in tempContents {
        if let creationDate = try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
           creationDate < limitDate {
          try? fileManager.removeItem(at: fileURL)
        }
      }
      
      DispatchQueue.main.async {
        loadRecent()
      }
    }
  }
}

struct ScreenshotGridItem: View {
  let path: String
  let thumbnail: NSImage?
  let onLoad: () -> Void
  let onOpen: () -> Void
  let onCopy: () -> Void
  let onShare: () -> Void
  let onDelete: () -> Void
  
  @State private var isHovered = false
  
  var body: some View {
    let url = URL(fileURLWithPath: path)
    
    VStack(alignment: .leading, spacing: 4) {
      ZStack(alignment: .topTrailing) {
        if let thumbnail {
          Image(nsImage: thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 140, height: 95)
            .clipped()
            .cornerRadius(6)
        } else {
          ZStack {
            Color.gray.opacity(0.28)
            ProgressView()
              .controlSize(.small)
          }
          .frame(width: 140, height: 95)
          .cornerRadius(6)
        }
        
        if isHovered {
          Color.black.opacity(0.2)
            .cornerRadius(6)
          
          Button(action: onDelete) {
            Image(systemName: "trash")
              .font(.system(size: 10, weight: .bold))
              .foregroundColor(.white)
              .padding(5)
              .background(Color.red)
              .clipShape(Circle())
          }
          .buttonStyle(.plain)
          .padding(6)
        }
      }
      .onAppear(perform: onLoad)
      .onHover { isHovered = $0 }
      .onTapGesture(perform: onOpen)
      
      Text(url.lastPathComponent)
        .font(.system(size: 10))
        .foregroundColor(.secondary)
        .lineLimit(1)
        .frame(width: 140, alignment: .leading)
    }
    .contextMenu {
      Button("Edit", action: onOpen)
      Button("Copy to Clipboard", action: onCopy)
      Button("Share...", action: onShare)
      Button("Show in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([url])
      }
      Divider()
      Button("Delete", role: .destructive, action: onDelete)
    }
  }
}

private func makeThumbnailImage(path: String, maxPixelSize: CGFloat) -> NSImage? {
  let url = URL(fileURLWithPath: path) as CFURL
  let sourceOptions = [
    kCGImageSourceShouldCache: false
  ] as CFDictionary
  guard let source = CGImageSourceCreateWithURL(url, sourceOptions) else {
    return nil
  }
  
  let thumbnailOptions = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceShouldCacheImmediately: true,
    kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize)
  ] as CFDictionary
  
  guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
    return nil
  }
  
  return NSImage(
    cgImage: cgImage,
    size: CGSize(width: cgImage.width, height: cgImage.height)
  )
}

private func loadImageForRendering(path: String) -> NSImage? {
  let url = URL(fileURLWithPath: path) as CFURL
  let options = [
    kCGImageSourceShouldCache: true,
    kCGImageSourceShouldCacheImmediately: true
  ] as CFDictionary
  
  if let source = CGImageSourceCreateWithURL(url, options),
     let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options) {
    return NSImage(
      cgImage: cgImage,
      size: CGSize(width: cgImage.width, height: cgImage.height)
    )
  }
  
  return NSImage(contentsOfFile: path)
}

// MARK: - Settings Store
class SettingsStore: ObservableObject {
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

  init() {
    load()
  }

  func load() {
    let key = "flutter.qpark_shot.app_settings.v1"
    guard let jsonString = UserDefaults.standard.string(forKey: key),
          let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return
    }
    if let theme = json["themePreference"] as? String {
      self.themePreference = theme
    }
    if let hotkey = json["hotkey"] as? [String: Any] {
      self.hotkeyEnabled = hotkey["enabled"] as? Bool ?? true
      self.hotkeyKey = hotkey["key"] as? String ?? "C"
      self.hotkeyModifiers = hotkey["modifiers"] as? [String] ?? ["command", "shift"]
    }
    if let watermark = json["watermark"] as? [String: Any] {
      self.watermarkLayoutMode = watermark["layoutMode"] as? String ?? "single"
      self.watermarkSpacing = watermark["spacing"] as? Double ?? 150.0
      self.watermarkTilePattern = watermark["tilePattern"] as? String ?? "aligned"
      self.watermarkTileRandomness = watermark["tileRandomness"] as? Double ?? 0.45
      if let textSettings = watermark["text"] as? [String: Any] {
        self.watermarkTextEnabled = textSettings["enabled"] as? Bool ?? false
        self.watermarkText = textSettings["text"] as? String ?? "QPARK Shot"
        self.watermarkTextColor = textSettings["color"] as? String ?? "#FFFFFF"
      }
      if let logoSettings = watermark["logo"] as? [String: Any] {
        self.watermarkLogoEnabled = logoSettings["enabled"] as? Bool ?? false
        self.watermarkLogoPath = logoSettings["path"] as? String ?? ""
        self.watermarkSize = logoSettings["size"] as? Double ?? 120.0
        self.watermarkOpacity = logoSettings["opacity"] as? Double ?? 0.5
        self.watermarkPosition = logoSettings["positionMode"] as? String ?? "bottomRight"
      }
    }
    if let cleanup = json["cleanup"] as? [String: Any] {
      self.cleanupMode = cleanup["mode"] as? String ?? "never"
      self.cleanupIncludeSaved = cleanup["includeSavedFiles"] as? Bool ?? false
      if let durationSec = cleanup["durationSeconds"] as? Double {
        self.cleanupDurationHours = durationSec / 3600.0
      }
      self.saveDirectory = cleanup["saveDirectory"] as? String ?? ""
    }
  }

  func save() {
    let key = "flutter.qpark_shot.app_settings.v1"
    let json: [String: Any] = [
      "themePreference": themePreference,
      "hotkey": [
        "enabled": hotkeyEnabled,
        "key": hotkeyKey,
        "modifiers": hotkeyModifiers
      ],
      "watermark": [
        "layoutMode": watermarkLayoutMode,
        "spacing": watermarkSpacing,
        "tilePattern": watermarkTilePattern,
        "tileRandomness": watermarkTileRandomness,
        "text": [
          "enabled": watermarkTextEnabled,
          "text": watermarkText,
          "color": watermarkTextColor
        ],
        "logo": [
          "enabled": watermarkLogoEnabled,
          "path": watermarkLogoPath,
          "size": watermarkSize,
          "opacity": watermarkOpacity,
          "positionMode": watermarkPosition
        ]
      ],
      "cleanup": [
        "mode": cleanupMode,
        "includeSavedFiles": cleanupIncludeSaved,
        "durationSeconds": cleanupDurationHours * 3600.0,
        "saveDirectory": saveDirectory
      ]
    ]
    if let data = try? JSONSerialization.data(withJSONObject: json, options: []),
       let jsonString = String(data: data, encoding: .utf8) {
      UserDefaults.standard.set(jsonString, forKey: key)
      UserDefaults.standard.synchronize()
    }
    
    // Notify AppDelegate to re-register hotkey
    AppDelegate.shared.syncHotkeySettings()
    AppDelegate.shared.applyThemePreference()
  }
}

// MARK: - Watermark Live Preview Card
struct WatermarkPreviewView: View {
  let layoutMode: String
  let textEnabled: Bool
  let text: String
  let textColor: String
  let logoEnabled: Bool
  let logoPath: String
  let opacity: Double
  let position: String
  let logoSize: Double
  let spacing: Double
  let tilePattern: String
  let tileRandomness: Double
  
  @State private var logoImage: NSImage? = nil
  @State private var logoLoadRequestID = UUID()
  
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Live Preview")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)
      
      ZStack {
        // Mock landscape gradient screenshot
        LinearGradient(
          gradient: Gradient(colors: [Color.blue.opacity(0.7), Color.indigo.opacity(0.8)]),
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .cornerRadius(8)
        
        // Mock screenshot details (e.g. status bar at the top)
        VStack {
          HStack(spacing: 4) {
            Circle().fill(Color.white.opacity(0.4)).frame(width: 6, height: 6)
            Circle().fill(Color.white.opacity(0.4)).frame(width: 6, height: 6)
            Circle().fill(Color.white.opacity(0.4)).frame(width: 6, height: 6)
            Spacer()
            RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.3)).frame(width: 30, height: 6)
          }
          .padding(8)
          Spacer()
        }
        
        // Watermark layouts
        watermarkLayout
      }
      .frame(width: 170, height: 115)
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
      )
      .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
    }
    .onAppear(perform: loadLogoPreview)
    .onChange(of: logoPath) { _ in loadLogoPreview() }
    .onChange(of: logoEnabled) { _ in loadLogoPreview() }
  }
  
  private func getAlignment(for position: String) -> SwiftUI.Alignment {
    switch position {
    case "bottomRight": return SwiftUI.Alignment.bottomTrailing
    case "bottomLeft": return SwiftUI.Alignment.bottomLeading
    case "topRight": return SwiftUI.Alignment.topTrailing
    case "topLeft": return SwiftUI.Alignment.topLeading
    default: return SwiftUI.Alignment.center
    }
  }
  
  private var watermarkLayout: some View {
    GeometryReader { geo in
      if layoutMode == "tiled" {
        Canvas { context, size in
          let diagonal = sqrt(size.width * size.width + size.height * size.height)
          let stepX = max(40.0, spacing / 3.0)
          let stepY = max(30.0, spacing / 4.0)
          
          context.rotate(by: Angle(degrees: -30))
          
          // Let's resolve the logo image if enabled
          var resolvedLogo: GraphicsContext.ResolvedImage? = nil
          var logoW: CGFloat = 0
          var logoH: CGFloat = 0
          if logoEnabled {
            if let img = logoImage {
              resolvedLogo = context.resolve(Image(nsImage: img))
              logoW = max(10, min(25, logoSize / 10))
              logoH = img.size.height * (logoW / img.size.width)
            } else {
              resolvedLogo = context.resolve(Image(systemName: "photo.circle.fill"))
              logoW = 14
              logoH = 14
            }
          }
          
          var rowIndex = 0
          for y in stride(from: -diagonal, to: diagonal, by: stepY) {
            let rowOffset = tilePattern == "brick" || tilePattern == "random"
              ? (rowIndex.isMultiple(of: 2) ? 0 : stepX / 2)
              : 0
            var columnIndex = 0
            for x in stride(from: -diagonal, to: diagonal, by: stepX) {
              let jitterLimit = tilePattern == "random"
                ? min(stepX, stepY) * CGFloat(tileRandomness) * 0.35
                : 0
              let drawX = x + rowOffset + deterministicTileJitter(row: rowIndex, column: columnIndex, salt: 1) * jitterLimit
              let drawY = y + deterministicTileJitter(row: rowIndex, column: columnIndex, salt: 2) * jitterLimit
              
              if let logo = resolvedLogo {
                let logoRect = CGRect(x: drawX - logoW / 2, y: drawY - logoH / 2, width: logoW, height: logoH)
                context.draw(logo, in: logoRect)
              }
              
              if textEnabled && !text.isEmpty {
                let txt = context.resolve(Text(text)
                  .font(.system(size: 6, weight: .bold))
                  .foregroundColor(Color(hexString: textColor)))
                let textY = logoEnabled ? (drawY - logoH / 2 - 8) : (drawY - 3)
                context.draw(txt, at: CGPoint(x: drawX, y: textY), anchor: .top)
              }
              columnIndex += 1
            }
            rowIndex += 1
          }
        }
        .opacity(opacity)
        .ignoresSafeArea()
      } else {
        VStack(spacing: 4) {
          if logoEnabled, let img = logoImage {
            Image(nsImage: img)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: CGFloat(max(15, min(40, logoSize / 5))))
              .opacity(opacity)
          } else if logoEnabled {
            Image(systemName: "photo.circle.fill")
              .font(.system(size: 16))
              .foregroundColor(.white)
              .opacity(opacity)
          }
          
          if textEnabled && !text.isEmpty {
            Text(text)
              .font(.system(size: 8, weight: .bold))
              .foregroundColor(Color(hexString: textColor))
              .lineLimit(1)
              .opacity(opacity)
          }
        }
        .padding(8)
        .frame(width: geo.size.width, height: geo.size.height, alignment: getAlignment(for: position))
      }
    }
  }
  
  private func loadLogoPreview() {
    let requestID = UUID()
    logoLoadRequestID = requestID
    
    guard logoEnabled, !logoPath.isEmpty else {
      logoImage = nil
      return
    }
    
    let logoPathSnapshot = logoPath
    DispatchQueue.global(qos: .utility).async {
      let image = makeThumbnailImage(path: logoPathSnapshot, maxPixelSize: 180)
      DispatchQueue.main.async {
        guard logoLoadRequestID == requestID else { return }
        logoImage = image
      }
    }
  }
}

// MARK: - Settings Card
struct SettingsCard<Content: View>: View {
  let content: Content
  
  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      content
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(VisualEffectView(material: .contentBackground, blendingMode: .withinWindow))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    )
  }
}

// MARK: - Settings View
struct SettingsView: View {
  @ObservedObject var store: SettingsStore
  var onBack: () -> Void = {}
  @State private var activeTab = 0
  
  var body: some View {
    HStack(spacing: 0) {
      // Sidebar on the left
      VStack(alignment: .leading, spacing: 0) {
        Button(action: onBack) {
          Label("Gallery", systemImage: "chevron.left")
            .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
        
        // App header
        HStack(spacing: 10) {
          Image(systemName: "camera.viewfinder.circle.fill")
            .font(.system(size: 26))
            .foregroundColor(.accentColor)
          VStack(alignment: .leading, spacing: 1) {
            Text("QPARK Shot")
              .font(.system(size: 13, weight: .bold))
            Text("Preferences")
              .font(.system(size: 10))
              .foregroundColor(.secondary)
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
        
        // Navigation items
        VStack(spacing: 4) {
          sidebarButton(index: 0, label: "Appearance", icon: "circle.lefthalf.filled", color: .teal)
          sidebarButton(index: 1, label: "Hotkeys", icon: "keyboard", color: .blue)
          sidebarButton(index: 2, label: "Watermark", icon: "signature", color: .purple)
          sidebarButton(index: 3, label: "Storage", icon: "folder.fill", color: .orange)
          sidebarButton(index: 4, label: "About", icon: "info.circle.fill", color: .gray)
        }
        .padding(.horizontal, 8)
        
        Spacer()
      }
      .frame(width: 170)
      .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
      
      Divider()
      
      // Detail content area on the right
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          switch activeTab {
          case 0:
            appearanceTab
          case 1:
            hotkeysTab
          case 2:
            watermarkTab
          case 3:
            storageTab
          default:
            aboutTab
          }
        }
        .padding(20)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
  
  private func sidebarButton(index: Int, label: String, icon: String, color: Color) -> some View {
    Button(action: {
      activeTab = index
    }) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.white)
          .frame(width: 20, height: 20)
          .background(color)
          .cornerRadius(5)
        
        Text(label)
          .font(.system(size: 12, weight: activeTab == index ? .medium : .regular))
          .foregroundColor(activeTab == index ? .primary : .primary.opacity(0.8))
        
        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(activeTab == index ? Color.primary.opacity(0.1) : Color.clear)
      )
    }
    .buttonStyle(.plain)
  }
  
  private func sectionHeader(title: String, icon: String, color: Color) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(color)
      Text(title)
        .font(.system(size: 16, weight: .bold))
    }
    .padding(.bottom, 4)
  }
  
  private var appearanceTab: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(title: "Appearance", icon: "circle.lefthalf.filled", color: .teal)
      
      SettingsCard {
        VStack(alignment: .leading, spacing: 10) {
          Text("Theme")
            .font(.system(size: 12, weight: .semibold))
          
          Picker("", selection: Binding(
            get: { store.themePreference },
            set: { store.themePreference = $0; store.save() }
          )) {
            Label("System", systemImage: "display").tag("system")
            Label("Light", systemImage: "sun.max").tag("light")
            Label("Dark", systemImage: "moon").tag("dark")
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          
          Text(appearanceDescription)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
      }
    }
  }
  
  private var appearanceDescription: String {
    switch store.themePreference {
    case "light":
      return "Forces the light appearance for the app window and glass materials."
    case "dark":
      return "Forces the dark appearance for the app window and glass materials."
    default:
      return "Follows the current macOS system appearance automatically."
    }
  }
  
  private var hotkeysTab: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(title: "Hotkeys", icon: "keyboard", color: .blue)
      
      SettingsCard {
        Toggle("Enable Global Capture Hotkey", isOn: Binding(
          get: { store.hotkeyEnabled },
          set: { store.hotkeyEnabled = $0; store.save() }
        ))
        .toggleStyle(.switch)
        .font(.system(size: 12, weight: .semibold))
        
        if store.hotkeyEnabled {
          Divider()
          
          HStack(spacing: 8) {
            Text("Shortcut:")
              .font(.system(size: 12))
            
            Toggle("Cmd", isOn: Binding(
              get: { store.hotkeyModifiers.contains("command") },
              set: { on in
                if on {
                  if !store.hotkeyModifiers.contains("command") { store.hotkeyModifiers.append("command") }
                } else {
                  store.hotkeyModifiers.removeAll { $0 == "command" }
                }
                store.save()
              }
            ))
            .toggleStyle(.checkbox)
            
            Toggle("Shift", isOn: Binding(
              get: { store.hotkeyModifiers.contains("shift") },
              set: { on in
                if on {
                  if !store.hotkeyModifiers.contains("shift") { store.hotkeyModifiers.append("shift") }
                } else {
                  store.hotkeyModifiers.removeAll { $0 == "shift" }
                }
                store.save()
              }
            ))
            .toggleStyle(.checkbox)
            
            Toggle("Option", isOn: Binding(
              get: { store.hotkeyModifiers.contains("option") },
              set: { on in
                if on {
                  if !store.hotkeyModifiers.contains("option") { store.hotkeyModifiers.append("option") }
                } else {
                  store.hotkeyModifiers.removeAll { $0 == "option" }
                }
                store.save()
              }
            ))
            .toggleStyle(.checkbox)
            
            Toggle("Ctrl", isOn: Binding(
              get: { store.hotkeyModifiers.contains("control") },
              set: { on in
                if on {
                  if !store.hotkeyModifiers.contains("control") { store.hotkeyModifiers.append("control") }
                } else {
                  store.hotkeyModifiers.removeAll { $0 == "control" }
                }
                store.save()
              }
            ))
            .toggleStyle(.checkbox)
            
            TextField("Key", text: Binding(
              get: { store.hotkeyKey },
              set: {
                let cleaned = String($0.prefix(1)).uppercased()
                store.hotkeyKey = cleaned
                store.save()
              }
            ))
            .frame(width: 40)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
          }
          .font(.system(size: 11))
        }
      }
    }
  }
  
  private var watermarkTab: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(title: "Watermark Settings", icon: "signature", color: .purple)
      
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 12) {
          // Layout selection card
          SettingsCard {
            VStack(alignment: .leading, spacing: 4) {
              Text("Layout Mode")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
              Picker("", selection: Binding(
                get: { store.watermarkLayoutMode },
                set: { store.watermarkLayoutMode = $0; store.save() }
              )) {
                Text("Single Location").tag("single")
                Text("Tiled Diagonal").tag("tiled")
              }
              .pickerStyle(.segmented)
            }
          }
          
          // Text Watermark Card
          SettingsCard {
            Toggle("Enable Text Watermark", isOn: Binding(
              get: { store.watermarkTextEnabled },
              set: { store.watermarkTextEnabled = $0; store.save() }
            ))
            .toggleStyle(.switch)
            .font(.system(size: 12, weight: .semibold))
            
            if store.watermarkTextEnabled {
              TextField("Watermark Text", text: Binding(
                get: { store.watermarkText },
                set: { store.watermarkText = $0; store.save() }
              ))
              .textFieldStyle(.roundedBorder)

              HStack {
                Text("Text Color:")
                  .font(.system(size: 11))
                Spacer()
                ColorPicker("", selection: Binding(
                  get: { Color(hexString: store.watermarkTextColor) },
                  set: { store.watermarkTextColor = hexString(from: $0); store.save() }
                ), supportsOpacity: false)
                .labelsHidden()
              }
            }
          }
          
          // Logo Watermark Card
          SettingsCard {
            Toggle("Enable Logo Watermark", isOn: Binding(
              get: { store.watermarkLogoEnabled },
              set: { store.watermarkLogoEnabled = $0; store.save() }
            ))
            .toggleStyle(.switch)
            .font(.system(size: 12, weight: .semibold))
            
            if store.watermarkLogoEnabled {
              VStack(alignment: .leading, spacing: 8) {
                HStack {
                  TextField("Logo Path", text: Binding(
                    get: { store.watermarkLogoPath.isEmpty ? "Select image..." : store.watermarkLogoPath },
                    set: { _ in }
                  ))
                  .textFieldStyle(.roundedBorder)
                  .disabled(true)
                  
                  Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.allowedContentTypes = [.image]
                    if panel.runModal() == .OK {
                      store.watermarkLogoPath = panel.url?.path ?? ""
                      store.save()
                    }
                  }
                }
                
                HStack {
                  Text("Logo Size:")
                    .font(.system(size: 11))
                  Slider(value: Binding(
                    get: { store.watermarkSize },
                    set: { store.watermarkSize = $0; store.save() }
                  ), in: 50...300)
                  Text("\(Int(store.watermarkSize))px")
                    .font(.system(size: 11))
                    .frame(width: 45, alignment: .trailing)
                }
              }
            }
          }
          
          // Formatting Card
          SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
              if store.watermarkLayoutMode == "single" {
                HStack {
                  Text("Position:")
                  Spacer()
                  Picker("", selection: Binding(
                    get: { store.watermarkPosition },
                    set: { store.watermarkPosition = $0; store.save() }
                  )) {
                    Text("Bottom Right").tag("bottomRight")
                    Text("Bottom Left").tag("bottomLeft")
                    Text("Top Right").tag("topRight")
                    Text("Top Left").tag("topLeft")
                    Text("Center").tag("center")
                  }
                  .pickerStyle(.menu)
                  .frame(width: 130)
                }
                Divider()
              }
              
              HStack {
                Text("Opacity:")
                Slider(value: Binding(
                  get: { store.watermarkOpacity },
                  set: { store.watermarkOpacity = $0; store.save() }
                ), in: 0.1...1.0)
                Text(String(format: "%.0f%%", store.watermarkOpacity * 100))
                  .frame(width: 40, alignment: .trailing)
              }
            }
            .font(.system(size: 11))
          }
          if store.watermarkLayoutMode == "tiled" {
            SettingsCard {
              VStack(alignment: .leading, spacing: 8) {
                HStack {
                  Text("Pattern:")
                  Spacer()
                  Picker("", selection: Binding(
                    get: { store.watermarkTilePattern },
                    set: { store.watermarkTilePattern = $0; store.save() }
                  )) {
                    Text("Aligned").tag("aligned")
                    Text("Brick").tag("brick")
                    Text("Chaos").tag("random")
                  }
                  .pickerStyle(.menu)
                  .frame(width: 110)
                }
                
                Text("Watermark Density (Spacing):")
                  .font(.system(size: 10, weight: .bold))
                  .foregroundColor(.secondary)
                HStack {
                  Slider(value: Binding(
                    get: { store.watermarkSpacing },
                    set: { store.watermarkSpacing = $0; store.save() }
                  ), in: 80...400)
                  Text("\(Int(store.watermarkSpacing))px")
                    .font(.system(size: 11))
                    .frame(width: 45, alignment: .trailing)
                }
                
                if store.watermarkTilePattern == "random" {
                  HStack {
                    Text("Chaos:")
                    Slider(value: Binding(
                      get: { store.watermarkTileRandomness },
                      set: { store.watermarkTileRandomness = $0; store.save() }
                    ), in: 0...1)
                    Text(String(format: "%.0f%%", store.watermarkTileRandomness * 100))
                      .frame(width: 40, alignment: .trailing)
                  }
                }
              }
              .font(.system(size: 11))
            }
          }
        }
        .frame(width: 260)
        
        Spacer()
        
        VStack {
          WatermarkPreviewView(
            layoutMode: store.watermarkLayoutMode,
            textEnabled: store.watermarkTextEnabled,
            text: store.watermarkText,
            textColor: store.watermarkTextColor,
            logoEnabled: store.watermarkLogoEnabled,
            logoPath: store.watermarkLogoPath,
            opacity: store.watermarkOpacity,
            position: store.watermarkPosition,
            logoSize: store.watermarkSize,
            spacing: store.watermarkSpacing,
            tilePattern: store.watermarkTilePattern,
            tileRandomness: store.watermarkTileRandomness
          )
          Spacer()
        }
        .padding(.top, 4)
      }
    }
  }
  
  private var storageTab: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(title: "Storage & Cache", icon: "folder.fill", color: .orange)
      
      SettingsCard {
        Text("Save Location")
          .font(.system(size: 12, weight: .bold))
        
        HStack {
          TextField("Default Pictures Folder", text: Binding(
            get: { store.saveDirectory.isEmpty ? "Default (Pictures/QPARK Shot)" : store.saveDirectory },
            set: { _ in }
          ))
          .textFieldStyle(.roundedBorder)
          .disabled(true)
          
          Button("Browse...") {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK {
              store.saveDirectory = panel.url?.path ?? ""
              store.save()
            }
          }
        }
      }
      
      SettingsCard {
        Picker("Cleanup Policy:", selection: Binding(
          get: { store.cleanupMode },
          set: { store.cleanupMode = $0; store.save() }
        )) {
          Text("Never Delete").tag("never")
          Text("Delete After Duration").tag("afterDuration")
        }
        .pickerStyle(.menu)
        
        if store.cleanupMode == "afterDuration" {
          Divider()
          
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Keep Screenshots for:")
              Slider(value: Binding(
                get: { store.cleanupDurationHours },
                set: { store.cleanupDurationHours = $0; store.save() }
              ), in: 1...168)
              Text("\(Int(store.cleanupDurationHours)) hours")
                .frame(width: 80, alignment: .trailing)
            }
            
            Toggle("Include manually saved files in cleanup", isOn: Binding(
              get: { store.cleanupIncludeSaved },
              set: { store.cleanupIncludeSaved = $0; store.save() }
            ))
            .toggleStyle(.checkbox)
          }
          .font(.system(size: 11))
        }
      }
    }
  }
  
  private var aboutTab: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(title: "About QPARK Shot", icon: "info.circle.fill", color: .gray)
      
      SettingsCard {
        VStack(alignment: .center, spacing: 10) {
          Spacer().frame(height: 6)
          Image(systemName: "camera.viewfinder.circle.fill")
            .font(.system(size: 54))
            .foregroundColor(.accentColor)
          
          Text("QPARK Shot")
            .font(.system(size: 18, weight: .bold))
          
          Text("Version 1.0.0")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
          
          Link("QPARK.IO", destination: URL(string: "https://qpark.io")!)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.accentColor)
          
          Text("A professional screenshots workspace utility.")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
          
          Divider()
          
          Text("Copyright © 2026 QPARK. All rights reserved.")
            .font(.system(size: 9))
            .foregroundColor(.secondary)
          Spacer().frame(height: 6)
        }
        .frame(maxWidth: .infinity)
      }
    }
  }
}

// MARK: - Editor View
struct EditorView: View {
  let imagePath: String
  var onClose: () -> Void = {}
  var onSave: () -> Void
  
  @State private var image: NSImage? = nil
  @State private var annotations: [Annotation] = []
  @State private var undoStack: [[Annotation]] = []
  @State private var redoStack: [[Annotation]] = []
  
  @State private var tool: ToolType = .freehand
  @State private var color: Color = .red
  @State private var strokeWidth: CGFloat = 4.0
  @State private var textInput: String = "Text Annotation"
  @State private var cropRect: CGRect? = nil
  @State private var previewImage: NSImage? = nil
  @State private var previewError: String? = nil
  @State private var isPreviewRendering = false
  @State private var isPreviewPresented = false
  @State private var previewRequestID = UUID()
  @State private var imageLoadRequestID = UUID()
  @State private var exportRequestID = UUID()
  @State private var isExporting = false
  
  var body: some View {
    VStack(spacing: 0) {
      // Editor Toolbar
      HStack(spacing: 12) {
        Button(action: onClose) {
          Image(systemName: "chevron.left")
        }
        .help("Back to Gallery")
        
        Picker("Tool", selection: $tool) {
          Image(systemName: "crop").tag(ToolType.select)
          Image(systemName: "scribble").tag(ToolType.freehand)
          Image(systemName: "arrow.up.forward").tag(ToolType.arrow)
          Image(systemName: "square").tag(ToolType.rectangle)
          Image(systemName: "textformat").tag(ToolType.text)
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
        
        ColorPicker("", selection: $color)
        
        Picker("Size", selection: $strokeWidth) {
          Text("Thin").tag(CGFloat(2.0))
          Text("Medium").tag(CGFloat(4.0))
          Text("Thick").tag(CGFloat(8.0))
          Text("Heavy").tag(CGFloat(14.0))
        }
        .frame(width: 90)
        
        if tool == .text {
          TextField("Text", text: $textInput)
            .textFieldStyle(.roundedBorder)
            .frame(width: 140)
        }
        
        Spacer()
        
        Button(action: undo) {
          Image(systemName: "arrow.uturn.backward")
        }
        .disabled(undoStack.isEmpty)
        .help("Undo")
        
        Button(action: redo) {
          Image(systemName: "arrow.uturn.forward")
        }
        .disabled(redoStack.isEmpty)
        .help("Redo")
        
        Divider().frame(height: 24)
        
        if isExporting {
          ProgressView()
            .controlSize(.small)
            .help("Exporting")
        }
        
        Button(action: showPreview) {
          Image(systemName: "eye")
        }
        .disabled(image == nil || isExporting)
        .help("Preview with Watermarks")
        
        Button(action: copyToClipboard) {
          Image(systemName: "doc.on.doc")
        }
        .disabled(image == nil || isExporting)
        .help("Copy to Clipboard")
        
        Button(action: shareImage) {
          Image(systemName: "square.and.arrow.up")
        }
        .disabled(image == nil || isExporting)
        .help("Share")
        
        Button(action: saveImageToFile) {
          HStack {
            Image(systemName: "square.and.arrow.down")
            Text("Save")
          }
        }
        .disabled(image == nil || isExporting)
        .buttonStyle(.borderedProminent)
      }
      .padding(.top, 8)
      .padding(.horizontal, 12)
      .padding(.bottom, 8)
      .background(Color.clear)
      
      Divider()
      
      // Editor Canvas
      GeometryReader { geo in
        if let img = image {
          ZStack {
            DrawingCanvas(
              image: img,
              annotations: $annotations,
              currentTool: $tool,
              currentColor: $color,
              currentStrokeWidth: $strokeWidth,
              textInput: $textInput,
              cropRect: $cropRect,
              onAction: {
                recordUndo()
              }
            )
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    .frame(minWidth: 800, minHeight: 550)
    .onAppear {
      loadEditorImage()
    }
    .onChange(of: imagePath) { _ in
      loadEditorImage()
    }
    .overlay {
      if isPreviewPresented {
        ExportPreviewOverlay(
          image: previewImage,
          isRendering: isPreviewRendering,
          errorMessage: previewError,
          onClose: closePreview
        )
        .transition(.opacity)
      }
    }
  }
  
  private func recordUndo() {
    undoStack.append(annotations)
    redoStack.removeAll()
  }
  
  private func loadEditorImage() {
    let requestID = UUID()
    imageLoadRequestID = requestID
    image = nil
    annotations = []
    undoStack = []
    redoStack = []
    cropRect = nil
    
    let imagePathSnapshot = imagePath
    DispatchQueue.global(qos: .userInitiated).async {
      let loadedImage = loadImageForRendering(path: imagePathSnapshot)
      DispatchQueue.main.async {
        guard imageLoadRequestID == requestID else { return }
        image = loadedImage
        if loadedImage != nil {
          recordUndo()
        }
      }
    }
  }
  
  private func undo() {
    guard undoStack.count > 1 else { return }
    let current = undoStack.removeLast()
    redoStack.append(current)
    annotations = undoStack.last ?? []
  }
  
  private func redo() {
    guard let next = redoStack.popLast() else { return }
    undoStack.append(next)
    annotations = next
  }
  
  private func showPreview() {
    guard image != nil else { return }
    let requestID = UUID()
    previewRequestID = requestID
    previewImage = nil
    previewError = nil
    isPreviewRendering = true
    isPreviewPresented = true
    
    let imagePathSnapshot = imagePath
    let annotationsSnapshot = annotations
    let cropSnapshot = cropRect
    let watermarkSnapshot = WatermarkRenderSettings.current()
    
    DispatchQueue.global(qos: .userInitiated).async {
      let renderedImage: NSImage?
      if let renderImage = loadImageForRendering(path: imagePathSnapshot) {
        renderedImage = renderAnnotatedImage(
          image: renderImage,
          annotations: annotationsSnapshot,
          cropRect: cropSnapshot,
          watermark: watermarkSnapshot
        )
      } else {
        renderedImage = nil
      }
      
      DispatchQueue.main.async {
        guard previewRequestID == requestID else { return }
        isPreviewRendering = false
        if let renderedImage {
          previewImage = renderedImage
        } else {
          previewError = "Could not render preview."
        }
      }
    }
  }
  
  private func closePreview() {
    previewRequestID = UUID()
    isPreviewRendering = false
    isPreviewPresented = false
  }
  
  private func copyToClipboard() {
    renderExportedImageInBackground { finalImg in
      guard let finalImg else { return }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.writeObjects([finalImg])
    }
  }
  
  private func shareImage() {
    saveExportedImageInBackground(isTemporary: true) { path in
      guard let path else { return }
      let url = URL(fileURLWithPath: path)
      let picker = NSSharingServicePicker(items: [url])
      if let window = NSApp.keyWindow, let contentView = window.contentView {
        let rect = NSRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
        picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
      }
    }
  }
  
  private func saveImageToFile() {
    saveExportedImageInBackground(isTemporary: false) { path in
      if path != nil {
        onSave()
      }
    }
  }
  
  private func renderExportedImageInBackground(completion: @escaping (NSImage?) -> Void) {
    guard image != nil, !isExporting else { return }
    let requestID = UUID()
    exportRequestID = requestID
    isExporting = true
    
    let imagePathSnapshot = imagePath
    let annotationsSnapshot = annotations
    let cropSnapshot = cropRect
    let watermarkSnapshot = WatermarkRenderSettings.current()
    
    DispatchQueue.global(qos: .userInitiated).async {
      let renderedImage: NSImage?
      if let renderImage = loadImageForRendering(path: imagePathSnapshot) {
        renderedImage = renderAnnotatedImage(
          image: renderImage,
          annotations: annotationsSnapshot,
          cropRect: cropSnapshot,
          watermark: watermarkSnapshot
        )
      } else {
        renderedImage = nil
      }
      
      DispatchQueue.main.async {
        guard exportRequestID == requestID else { return }
        isExporting = false
        completion(renderedImage)
      }
    }
  }
  
  private func saveExportedImageInBackground(isTemporary: Bool, completion: @escaping (String?) -> Void) {
    guard image != nil, !isExporting else { return }
    let requestID = UUID()
    exportRequestID = requestID
    isExporting = true
    
    let imagePathSnapshot = imagePath
    let annotationsSnapshot = annotations
    let cropSnapshot = cropRect
    let watermarkSnapshot = WatermarkRenderSettings.current()
    
    DispatchQueue.global(qos: .userInitiated).async {
      let savedPath: String?
      if let renderImage = loadImageForRendering(path: imagePathSnapshot),
         let renderedImage = renderAnnotatedImage(
          image: renderImage,
          annotations: annotationsSnapshot,
          cropRect: cropSnapshot,
          watermark: watermarkSnapshot
         ) {
        savedPath = saveImage(image: renderedImage, isTemporary: isTemporary)
      } else {
        savedPath = nil
      }
      
      DispatchQueue.main.async {
        guard exportRequestID == requestID else { return }
        isExporting = false
        completion(savedPath)
      }
    }
  }
}

struct ExportPreviewOverlay: View {
  let image: NSImage?
  let isRendering: Bool
  let errorMessage: String?
  let onClose: () -> Void
  
  @State private var zoomScale: CGFloat = 1.0
  
  private let minZoom: CGFloat = 0.25
  private let maxZoom: CGFloat = 4.0
  
  var body: some View {
    GeometryReader { geo in
      let overlaySize = CGSize(
        width: max(geo.size.width - 24, 320),
        height: max(geo.size.height - 24, 260)
      )
      
      VStack(spacing: 0) {
        HStack(spacing: 8) {
          Label("Preview", systemImage: "eye")
            .font(.system(size: 13, weight: .semibold))
          
          Spacer()
          
          if image != nil {
            Button {
              zoomScale = max(minZoom, zoomScale - 0.25)
            } label: {
              Image(systemName: "minus.magnifyingglass")
            }
            .disabled(zoomScale <= minZoom)
            .help("Zoom out")
            
            Text("\(Int(zoomScale * 100))%")
              .font(.system(size: 11, weight: .medium, design: .monospaced))
              .frame(width: 44)
              .foregroundColor(.secondary)
            
            Button {
              zoomScale = min(maxZoom, zoomScale + 0.25)
            } label: {
              Image(systemName: "plus.magnifyingglass")
            }
            .disabled(zoomScale >= maxZoom)
            .help("Zoom in")
            
            Button("Fit") {
              zoomScale = 1.0
            }
            .help("Fit to window")
          }
          
          Divider()
            .frame(height: 22)
          
          Button("Done", action: onClose)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
        
        Divider()
        
        ZStack {
          if let image {
            previewImage(image, in: overlaySize)
          } else if isRendering {
            VStack(spacing: 12) {
              ProgressView()
              Text("Rendering preview...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            VStack(spacing: 12) {
              Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
              Text(errorMessage ?? "Preview is unavailable.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.86))
      }
      .frame(width: overlaySize.width, height: overlaySize.height)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 8)
      .padding(12)
    }
    .background(Color.black.opacity(0.45))
  }
  
  private func previewImage(_ image: NSImage, in containerSize: CGSize) -> some View {
    let availableWidth = max(containerSize.width - 56, 100)
    let availableHeight = max(containerSize.height - 104, 100)
    let fitScale = min(
      availableWidth / max(image.size.width, 1),
      availableHeight / max(image.size.height, 1),
      1
    )
    let displayScale = max(0.01, fitScale * zoomScale)
    let displaySize = CGSize(
      width: image.size.width * displayScale,
      height: image.size.height * displayScale
    )
    
    return ScrollView([.horizontal, .vertical]) {
      Image(nsImage: image)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
        .frame(width: displaySize.width, height: displaySize.height)
        .padding(20)
        .frame(
          minWidth: availableWidth,
          minHeight: availableHeight,
          alignment: .center
        )
    }
  }
}

// MARK: - Drawing Canvas Elements
enum ToolType {
  case select, freehand, arrow, rectangle, text
}

struct Annotation: Identifiable, Equatable {
  let id = UUID()
  var type: ToolType
  var color: Color
  var strokeWidth: CGFloat
  var points: [CGPoint] = []
  var text: String = ""
  var rect: CGRect = .zero
  
  static func == (lhs: Annotation, rhs: Annotation) -> Bool {
    lhs.id == rhs.id
  }
}

struct DrawingCanvas: View {
  let image: NSImage
  @Binding var annotations: [Annotation]
  @Binding var currentTool: ToolType
  @Binding var currentColor: Color
  @Binding var currentStrokeWidth: CGFloat
  @Binding var textInput: String
  @Binding var cropRect: CGRect?
  let onAction: () -> Void
  
  @State private var currentPoints: [CGPoint] = []
  @State private var dragStart: CGPoint?
  @State private var dragCurrent: CGPoint?

  var body: some View {
    GeometryReader { geo in
      let imageRect = fittedImageRect(imageSize: image.size, in: geo.size)
      let imageScale = imageRect.width / max(image.size.width, 1)
      
      ZStack {
        Image(nsImage: image)
          .resizable()
          .frame(width: imageRect.width, height: imageRect.height)
          .position(x: imageRect.midX, y: imageRect.midY)
        
        Canvas { context, _ in
          var drawingContext = context
          drawingContext.clip(to: Path(imageRect))
          drawingContext.translateBy(x: imageRect.minX, y: imageRect.minY)
          drawingContext.scaleBy(x: imageScale, y: imageScale)
          
          for annotation in annotations {
            var path = Path()
            switch annotation.type {
            case .freehand:
              if annotation.points.count > 1 {
                path.addLines(annotation.points)
                drawingContext.stroke(path, with: .color(annotation.color), lineWidth: annotation.strokeWidth)
              }
            case .rectangle:
              path.addRect(annotation.rect)
              drawingContext.stroke(path, with: .color(annotation.color), lineWidth: annotation.strokeWidth)
            case .arrow:
              if annotation.points.count == 2 {
                drawArrow(in: &drawingContext, from: annotation.points[0], to: annotation.points[1], color: annotation.color, width: annotation.strokeWidth)
              }
            default:
              break
            }
          }
          
          if let dragStart = dragStart, let dragCurrent = dragCurrent {
            var path = Path()
            switch currentTool {
            case .freehand:
              if currentPoints.count > 1 {
                path.addLines(currentPoints)
                drawingContext.stroke(path, with: .color(currentColor), lineWidth: currentStrokeWidth)
              }
            case .rectangle:
              let rect = CGRect(from: dragStart, to: dragCurrent)
              path.addRect(rect)
              drawingContext.stroke(path, with: .color(currentColor), lineWidth: currentStrokeWidth)
            case .arrow:
              drawArrow(in: &drawingContext, from: dragStart, to: dragCurrent, color: currentColor, width: currentStrokeWidth)
            case .select:
              let rect = CGRect(from: dragStart, to: dragCurrent)
              path.addRect(rect)
              drawingContext.stroke(path, with: .color(.blue), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            default:
              break
            }
          }
        }
        
        ForEach(annotations) { annotation in
          if annotation.type == .text, let firstPoint = annotation.points.first {
            Text(annotation.text)
              .font(.system(size: (annotation.strokeWidth * 3 + 12) * imageScale))
              .foregroundColor(annotation.color)
              .position(
                viewPoint(
                  for: firstPoint,
                  imageRect: imageRect,
                  imageSize: image.size
                )
              )
              .allowsHitTesting(false)
          }
        }
      }
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            if dragStart == nil {
              guard imageRect.contains(value.startLocation) else { return }
              let start = imagePoint(
                for: value.startLocation,
                imageRect: imageRect,
                imageSize: image.size
              )
              dragStart = start
              currentPoints = [start]
            }
            let point = imagePoint(
              for: value.location,
              imageRect: imageRect,
              imageSize: image.size
            )
            dragCurrent = point
            if currentTool == .freehand {
              currentPoints.append(point)
            }
          }
          .onEnded { value in
            guard let start = dragStart else { return }
            let end = imagePoint(
              for: value.location,
              imageRect: imageRect,
              imageSize: image.size
            )
            
            switch currentTool {
            case .freehand:
              if currentPoints.count > 1 {
                annotations.append(Annotation(type: .freehand, color: currentColor, strokeWidth: currentStrokeWidth, points: currentPoints))
                onAction()
              }
            case .rectangle:
              let rect = CGRect(from: start, to: end)
              annotations.append(Annotation(type: .rectangle, color: currentColor, strokeWidth: currentStrokeWidth, rect: rect))
              onAction()
            case .arrow:
              annotations.append(Annotation(type: .arrow, color: currentColor, strokeWidth: currentStrokeWidth, points: [start, end]))
              onAction()
            case .text:
              if !textInput.isEmpty {
                annotations.append(Annotation(type: .text, color: currentColor, strokeWidth: currentStrokeWidth, points: [start], text: textInput))
                onAction()
              }
            case .select:
              cropRect = CGRect(from: start, to: end)
              onAction()
            }
            
            dragStart = nil
            dragCurrent = nil
            currentPoints = []
          }
      )
    }
  }
  
  private func drawArrow(in context: inout GraphicsContext, from: CGPoint, to: CGPoint, color: Color, width: CGFloat) {
    var path = Path()
    path.move(to: from)
    path.addLine(to: to)
    context.stroke(path, with: .color(color), lineWidth: width)
    
    let angle = atan2(to.y - from.y, to.x - from.x)
    let arrowLength: CGFloat = width * 2 + 10
    
    let p1 = CGPoint(x: to.x - arrowLength * cos(angle - .pi/6), y: to.y - arrowLength * sin(angle - .pi/6))
    let p2 = CGPoint(x: to.x - arrowLength * cos(angle + .pi/6), y: to.y - arrowLength * sin(angle + .pi/6))
    
    var arrowHead = Path()
    arrowHead.move(to: to)
    arrowHead.addLine(to: p1)
    arrowHead.addLine(to: p2)
    arrowHead.closeSubpath()
    
    context.fill(arrowHead, with: .color(color))
  }
}

private func fittedImageRect(imageSize: CGSize, in availableSize: CGSize) -> CGRect {
  guard imageSize.width > 0,
        imageSize.height > 0,
        availableSize.width > 0,
        availableSize.height > 0 else {
    return .zero
  }
  
  let scale = min(
    availableSize.width / imageSize.width,
    availableSize.height / imageSize.height
  )
  let fittedSize = CGSize(
    width: imageSize.width * scale,
    height: imageSize.height * scale
  )
  return CGRect(
    x: (availableSize.width - fittedSize.width) / 2,
    y: (availableSize.height - fittedSize.height) / 2,
    width: fittedSize.width,
    height: fittedSize.height
  )
}

private func imagePoint(
  for viewPoint: CGPoint,
  imageRect: CGRect,
  imageSize: CGSize
) -> CGPoint {
  guard imageRect.width > 0, imageRect.height > 0 else {
    return .zero
  }
  
  let x = ((viewPoint.x - imageRect.minX) / imageRect.width) * imageSize.width
  let y = ((viewPoint.y - imageRect.minY) / imageRect.height) * imageSize.height
  return CGPoint(
    x: min(max(x, 0), imageSize.width),
    y: min(max(y, 0), imageSize.height)
  )
}

private func viewPoint(
  for imagePoint: CGPoint,
  imageRect: CGRect,
  imageSize: CGSize
) -> CGPoint {
  guard imageSize.width > 0, imageSize.height > 0 else {
    return imageRect.origin
  }
  
  return CGPoint(
    x: imageRect.minX + (imagePoint.x / imageSize.width) * imageRect.width,
    y: imageRect.minY + (imagePoint.y / imageSize.height) * imageRect.height
  )
}

// MARK: - CGRect Helpers
extension CGRect {
  init(from: CGPoint, to: CGPoint) {
    let x = min(from.x, to.x)
    let y = min(from.y, to.y)
    let width = abs(from.x - to.x)
    let height = abs(from.y - to.y)
    self.init(x: x, y: y, width: width, height: height)
  }
}

struct WatermarkRenderSettings {
  let textEnabled: Bool
  let text: String
  var textColor: String = "#FFFFFF"
  let logoEnabled: Bool
  let logoPath: String
  let opacity: Double
  let logoSize: Double
  let position: String
  let layoutMode: String
  let spacing: Double
  let tilePattern: String
  let tileRandomness: Double
  
  static func current(store: SettingsStore = SettingsStore.shared) -> WatermarkRenderSettings {
    WatermarkRenderSettings(
      textEnabled: store.watermarkTextEnabled,
      text: store.watermarkText,
      textColor: store.watermarkTextColor,
      logoEnabled: store.watermarkLogoEnabled,
      logoPath: store.watermarkLogoPath,
      opacity: store.watermarkOpacity,
      logoSize: store.watermarkSize,
      position: store.watermarkPosition,
      layoutMode: store.watermarkLayoutMode,
      spacing: store.watermarkSpacing,
      tilePattern: store.watermarkTilePattern,
      tileRandomness: store.watermarkTileRandomness
    )
  }
}

private func deterministicTileJitter(row: Int, column: Int, salt: Int) -> CGFloat {
  let seed = Double(row * 12_989 + column * 78_233 + salt * 37_719)
  let raw = sin(seed) * 43_758.5453
  let fraction = raw - floor(raw)
  return CGFloat(fraction * 2 - 1)
}

// MARK: - CoreGraphics Rendering & Save Actions
func renderAnnotatedImage(
  image: NSImage,
  annotations: [Annotation],
  cropRect: CGRect?,
  watermark: WatermarkRenderSettings = .current()
) -> NSImage? {
  let imageWidth = image.size.width
  let imageHeight = image.size.height
  let imageBounds = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
  let exportRect = normalizedCropRect(cropRect, in: imageBounds)
  let watermarkTarget = CGRect(
    x: exportRect.minX,
    y: imageHeight - exportRect.maxY,
    width: exportRect.width,
    height: exportRect.height
  )
  
  guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(imageWidth),
    pixelsHigh: Int(imageHeight),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else { return nil }
  
  rep.size = image.size
  
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  defer {
    NSGraphicsContext.restoreGraphicsState()
  }
  
  image.draw(in: NSRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

  let context = NSGraphicsContext.current?.cgContext
  
  for annotation in annotations {
    context?.saveGState()
    
    let cgColor = NSColor(annotation.color).cgColor
    context?.setStrokeColor(cgColor)
    context?.setFillColor(cgColor)
    context?.setLineWidth(annotation.strokeWidth)
    context?.setLineCap(.round)
    context?.setLineJoin(.round)
    
    switch annotation.type {
    case .freehand:
      if annotation.points.count > 1 {
        context?.beginPath()
        let first = annotation.points[0]
        context?.move(to: CGPoint(x: first.x, y: imageHeight - first.y))
        for i in 1..<annotation.points.count {
          let pt = annotation.points[i]
          context?.addLine(to: CGPoint(x: pt.x, y: imageHeight - pt.y))
        }
        context?.strokePath()
      }
    case .rectangle:
      let sourceRect = annotation.rect.standardized
      let flippedY = imageHeight - (sourceRect.origin.y + sourceRect.size.height)
      let renderRect = CGRect(
        x: sourceRect.origin.x,
        y: flippedY,
        width: sourceRect.size.width,
        height: sourceRect.size.height
      )
      context?.stroke(renderRect)
    case .arrow:
      if annotation.points.count == 2 {
        let from = CGPoint(
          x: annotation.points[0].x,
          y: imageHeight - annotation.points[0].y
        )
        let to = CGPoint(
          x: annotation.points[1].x,
          y: imageHeight - annotation.points[1].y
        )
        
        context?.beginPath()
        context?.move(to: from)
        context?.addLine(to: to)
        context?.strokePath()
        
        let angle = atan2(to.y - from.y, to.x - from.x)
        let arrowLength = annotation.strokeWidth * 2 + 10
        
        let p1 = CGPoint(x: to.x - arrowLength * cos(angle - .pi/6), y: to.y - arrowLength * sin(angle - .pi/6))
        let p2 = CGPoint(x: to.x - arrowLength * cos(angle + .pi/6), y: to.y - arrowLength * sin(angle + .pi/6))
        
        context?.beginPath()
        context?.move(to: to)
        context?.addLine(to: p1)
        context?.addLine(to: p2)
        context?.closePath()
        context?.fillPath()
      }
    case .text:
      if let first = annotation.points.first {
        let fontSize = annotation.strokeWidth * 3 + 12
        let textFont = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
          .font: textFont,
          .foregroundColor: NSColor(annotation.color)
        ]
        let textStr = annotation.text as NSString
        let textRect = NSRect(
          x: first.x,
          y: imageHeight - first.y - fontSize,
          width: imageWidth,
          height: imageHeight
        )
        textStr.draw(in: textRect, withAttributes: attributes)
      }
    default:
      break
    }
    
    context?.restoreGState()
  }
  
  // Render watermark
  let opacity = CGFloat(watermark.opacity)
  
  if watermark.layoutMode == "tiled" {
    context?.saveGState()
    context?.clip(to: watermarkTarget)
    context?.translateBy(x: watermarkTarget.midX, y: watermarkTarget.midY)
    
    let angle = -CGFloat.pi / 6
    context?.rotate(by: angle)
    
    let diagonal = sqrt(
      watermarkTarget.width * watermarkTarget.width +
        watermarkTarget.height * watermarkTarget.height
    )
    
    var loadedLogo: NSImage? = nil
    var logoW: CGFloat = 0
    var logoH: CGFloat = 0
    if watermark.logoEnabled && !watermark.logoPath.isEmpty {
      if let logoImg = NSImage(contentsOfFile: watermark.logoPath) {
        loadedLogo = logoImg
        logoW = CGFloat(watermark.logoSize)
        logoH = logoImg.size.height * (logoW / logoImg.size.width)
      }
    }
    
    var textFont: NSFont? = nil
    var textAttributes: [NSAttributedString.Key: Any] = [:]
    var textSize = CGSize.zero
    let hasText = watermark.textEnabled && !watermark.text.isEmpty
    let waterText = watermark.text as NSString
    
    if hasText {
      let fontSize = 20.0
      textFont = NSFont.boldSystemFont(ofSize: fontSize)
      textAttributes = [
        .font: textFont!,
        .foregroundColor: NSColor(hexString: watermark.textColor).withAlphaComponent(opacity)
      ]
      textSize = waterText.size(withAttributes: textAttributes)
    }
    
    let spacingX = CGFloat(watermark.spacing) * 1.5
    let spacingY = CGFloat(watermark.spacing) * 1.1
    
    var rowIndex = 0
    for y in stride(from: -diagonal, to: diagonal, by: spacingY) {
      let rowOffset = watermark.tilePattern == "brick" || watermark.tilePattern == "random"
        ? (rowIndex.isMultiple(of: 2) ? 0 : spacingX / 2)
        : 0
      var columnIndex = 0
      for x in stride(from: -diagonal, to: diagonal, by: spacingX) {
        let jitterLimit = watermark.tilePattern == "random"
          ? min(spacingX, spacingY) * CGFloat(watermark.tileRandomness) * 0.35
          : 0
        let drawX = x + rowOffset + deterministicTileJitter(row: rowIndex, column: columnIndex, salt: 1) * jitterLimit
        let drawY = y + deterministicTileJitter(row: rowIndex, column: columnIndex, salt: 2) * jitterLimit
        
        if let logoImg = loadedLogo {
          let logoRect = NSRect(
            x: drawX - logoW / 2,
            y: drawY - logoH / 2,
            width: logoW,
            height: logoH
          )
          logoImg.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: opacity)
        }
        
        if hasText {
          let textY: CGFloat
          if loadedLogo != nil {
            textY = drawY - logoH / 2 - textSize.height - 6.0
          } else {
            textY = drawY - textSize.height / 2
          }
          let textRect = NSRect(
            x: drawX - textSize.width / 2,
            y: textY,
            width: textSize.width,
            height: textSize.height
          )
          waterText.draw(in: textRect, withAttributes: textAttributes)
        }
        columnIndex += 1
      }
      rowIndex += 1
    }
    
    context?.restoreGState()
  } else {
    var logoHeightUsed: CGFloat = 0
    
    if watermark.logoEnabled, !watermark.logoPath.isEmpty,
       let logoImg = NSImage(contentsOfFile: watermark.logoPath) {
      let logoWidth = CGFloat(watermark.logoSize)
      let logoHeight = logoImg.size.height * (logoWidth / logoImg.size.width)
      logoHeightUsed = logoHeight
      
      let padding: CGFloat = min(
        16.0,
        min(watermarkTarget.width, watermarkTarget.height) * 0.12
      )
      var rect = NSRect.zero
      
      switch watermark.position {
      case "bottomRight":
        rect = NSRect(
          x: watermarkTarget.maxX - logoWidth - padding,
          y: watermarkTarget.minY + padding,
          width: logoWidth,
          height: logoHeight
        )
      case "bottomLeft":
        rect = NSRect(
          x: watermarkTarget.minX + padding,
          y: watermarkTarget.minY + padding,
          width: logoWidth,
          height: logoHeight
        )
      case "topRight":
        rect = NSRect(
          x: watermarkTarget.maxX - logoWidth - padding,
          y: watermarkTarget.maxY - logoHeight - padding,
          width: logoWidth,
          height: logoHeight
        )
      case "topLeft":
        rect = NSRect(
          x: watermarkTarget.minX + padding,
          y: watermarkTarget.maxY - logoHeight - padding,
          width: logoWidth,
          height: logoHeight
        )
      case "center":
        rect = NSRect(
          x: watermarkTarget.midX - logoWidth / 2,
          y: watermarkTarget.midY - logoHeight / 2,
          width: logoWidth,
          height: logoHeight
        )
      default:
        break
      }
      logoImg.draw(in: rect, from: .zero, operation: .sourceOver, fraction: CGFloat(watermark.opacity))
    }
    
    if watermark.textEnabled, !watermark.text.isEmpty {
      let waterText = watermark.text as NSString
      let fontSize = 24.0
      let font = NSFont.boldSystemFont(ofSize: fontSize)
      let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(hexString: watermark.textColor).withAlphaComponent(CGFloat(watermark.opacity))
      ]
      let size = waterText.size(withAttributes: attributes)
      let padding: CGFloat = min(
        16.0,
        min(watermarkTarget.width, watermarkTarget.height) * 0.12
      )
      var rect = NSRect.zero
      
      let yOffset = logoHeightUsed > 0 ? (logoHeightUsed + 8.0) : 0
      
      switch watermark.position {
      case "bottomRight":
        rect = NSRect(
          x: watermarkTarget.maxX - size.width - padding,
          y: watermarkTarget.minY + padding + yOffset,
          width: size.width,
          height: size.height
        )
      case "bottomLeft":
        rect = NSRect(
          x: watermarkTarget.minX + padding,
          y: watermarkTarget.minY + padding + yOffset,
          width: size.width,
          height: size.height
        )
      case "topRight":
        rect = NSRect(
          x: watermarkTarget.maxX - size.width - padding,
          y: watermarkTarget.maxY - size.height - padding - yOffset,
          width: size.width,
          height: size.height
        )
      case "topLeft":
        rect = NSRect(
          x: watermarkTarget.minX + padding,
          y: watermarkTarget.maxY - size.height - padding - yOffset,
          width: size.width,
          height: size.height
        )
      case "center":
        rect = NSRect(
          x: watermarkTarget.midX - size.width / 2,
          y: watermarkTarget.midY - size.height / 2 - yOffset,
          width: size.width,
          height: size.height
        )
      default:
        break
      }
      waterText.draw(in: rect, withAttributes: attributes)
    }
  }

  let finalImage = NSImage(size: image.size)
  finalImage.addRepresentation(rep)
  
  if exportRect != imageBounds {
    let targetRect = CGRect(
      x: exportRect.origin.x,
      y: exportRect.origin.y,
      width: exportRect.width,
      height: exportRect.height
    )
    guard let cgImg = rep.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let croppedCg = cgImg.cropping(to: targetRect) else {
      return finalImage
    }
    return NSImage(cgImage: croppedCg, size: exportRect.size)
  }
  
  return finalImage
}

private func normalizedCropRect(_ cropRect: CGRect?, in imageBounds: CGRect) -> CGRect {
  guard let cropRect else {
    return imageBounds
  }
  
  let crop = cropRect.standardized.intersection(imageBounds)
  if crop.isNull || crop.width < 2 || crop.height < 2 {
    return imageBounds
  }
  return crop
}

func saveImage(image: NSImage, isTemporary: Bool) -> String? {
  guard let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let pngData = rep.representation(using: .png, properties: [:]) else {
    return nil
  }
  
  let fileManager = FileManager.default
  let folderURL: URL
  
  if isTemporary {
    folderURL = fileManager.temporaryDirectory.appendingPathComponent("QPARK Shot")
  } else {
    let store = SettingsStore.shared
    if !store.saveDirectory.isEmpty {
      folderURL = URL(fileURLWithPath: store.saveDirectory)
    } else {
      let pictures = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first!
      folderURL = pictures.appendingPathComponent("QPARK Shot")
    }
  }
  
  try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
  
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyyMMdd_HHmmss"
  let filename = "Screenshot_" + formatter.string(from: Date()) + ".png"
  let fileURL = folderURL.appendingPathComponent(filename)
  
  do {
    try pngData.write(to: fileURL, options: .atomic)
    return fileURL.path
  } catch {
    return nil
  }
}

// MARK: - SwiftUI Bridge for NSVisualEffectView
struct VisualEffectView: NSViewRepresentable {
  let material: NSVisualEffectView.Material
  let blendingMode: NSVisualEffectView.BlendingMode
  
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = material
    view.blendingMode = blendingMode
    view.state = .active
    return view
  }
  
  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    nsView.material = material
    nsView.blendingMode = blendingMode
  }
}

// MARK: - Color <-> Hex helpers

private func parseHexRGB(_ hexString: String) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
  let hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
  guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
    return (1, 1, 1)
  }
  let r = CGFloat((value >> 16) & 0xFF) / 255.0
  let g = CGFloat((value >> 8) & 0xFF) / 255.0
  let b = CGFloat(value & 0xFF) / 255.0
  return (r, g, b)
}

extension NSColor {
  convenience init(hexString: String) {
    let rgb = parseHexRGB(hexString)
    self.init(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1.0)
  }
}

extension Color {
  init(hexString: String) {
    let rgb = parseHexRGB(hexString)
    self.init(.sRGB, red: Double(rgb.r), green: Double(rgb.g), blue: Double(rgb.b), opacity: 1.0)
  }
}

func hexString(from color: Color) -> String {
  let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
  let r = Int(round(ns.redComponent * 255))
  let g = Int(round(ns.greenComponent * 255))
  let b = Int(round(ns.blueComponent * 255))
  return String(format: "#%02X%02X%02X", r, g, b)
}
