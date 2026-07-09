import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

func isWithinRecentWindow(
  _ date: Date,
  now: Date = Date(),
  window: TimeInterval = 7 * 24 * 60 * 60
) -> Bool {
  date >= now.addingTimeInterval(-window) && date <= now
}

func shouldShowSessionStrip(isEnabled: Bool, itemCount: Int) -> Bool {
  isEnabled && itemCount > 1
}

enum WorkspaceSection: String, CaseIterable, Identifiable {
  case library
  case currentSession
  case favorites
  case recent
  case missing

  var id: String { rawValue }

  var titleKey: String {
    switch self {
    case .library: return "workspace.library"
    case .currentSession: return "workspace.current_session"
    case .favorites: return "workspace.favorites"
    case .recent: return "workspace.recent"
    case .missing: return "workspace.missing"
    }
  }

  var iconName: String {
    switch self {
    case .library: return "photo.on.rectangle.angled"
    case .currentSession: return "tray.full"
    case .favorites: return "star"
    case .recent: return "clock"
    case .missing: return "exclamationmark.triangle"
    }
  }
}

enum WorkspaceMode: Equatable {
  case library
  case captureReview(UUID)
  case editor(UUID)
  case permissionRequired
  case error(String)
}

enum WorkspaceStatusKind: Equatable {
  case info
  case success
  case warning
  case error

  var systemImage: String {
    switch self {
    case .info: return "info.circle.fill"
    case .success: return "checkmark.circle.fill"
    case .warning: return "exclamationmark.triangle.fill"
    case .error: return "xmark.octagon.fill"
    }
  }
}

struct WorkspaceStatus: Identifiable, Equatable {
  let id = UUID()
  let kind: WorkspaceStatusKind
  let message: String
}

struct LibraryShot: Identifiable, Equatable {
  let id: String
  let path: String
  let createdAt: Date
  var entry: GalleryIndexEntry

  var url: URL { URL(fileURLWithPath: path) }
}

@MainActor
final class WorkspaceStore: ObservableObject {
  static let shared = WorkspaceStore()

  @Published var selectedSection: WorkspaceSection = .library
  @Published var mode: WorkspaceMode = .library
  @Published var libraryShots: [LibraryShot] = []
  @Published var missingShots: [GalleryIndexEntry] = []
  @Published var selectedLibraryPath: String? = nil
  @Published var searchText: String = ""
  @Published var isInspectorVisible: Bool = true
  @Published var status: WorkspaceStatus? = nil
  @Published var isBusy: Bool = false
  @Published var isCapturing: Bool = false
  @Published private(set) var runningOCRPaths: Set<String> = []

  private var loadRequestID = UUID()
  private var statusDismissTask: Task<Void, Never>?
  private let fileManager = FileManager.default
  private let galleryIndex = GalleryIndexStore.shared

  private init() {}

  var statusMessage: String? {
    get { status?.message }
    set {
      statusDismissTask?.cancel()
      status = newValue.map { WorkspaceStatus(kind: .info, message: $0) }
    }
  }

  var displayedLibraryShots: [LibraryShot] {
    let sectionShots: [LibraryShot]
    switch selectedSection {
    case .favorites:
      sectionShots = libraryShots.filter(\.entry.favorite)
    case .recent:
      sectionShots = libraryShots.filter { isWithinRecentWindow($0.createdAt) }
    case .library, .currentSession:
      sectionShots = libraryShots
    case .missing:
      return []
    }

    let paths = sectionShots.map(\.path)
    let filteredPaths = SettingsStore.shared.gallerySearchIndexEnabled
      ? galleryIndex.pathsMatching(searchText, in: paths)
      : filterFilenames(paths, query: searchText)
    let orderedPaths = galleryIndex.pathsWithFavoritesFirst(filteredPaths)
    let byPath = Dictionary(uniqueKeysWithValues: sectionShots.map { ($0.path, $0) })
    return orderedPaths.compactMap { byPath[$0] }
  }

  var displayedMissingShots: [GalleryIndexEntry] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else { return missingShots }
    return missingShots.filter { value in
      ([value.fileName, value.path, value.ocrText] + value.tags)
        .joined(separator: " ")
        .lowercased()
        .contains(query)
    }
  }

  var selectedShot: LibraryShot? {
    guard let selectedLibraryPath else { return displayedLibraryShots.first }
    return libraryShots.first { $0.path == selectedLibraryPath }
  }

  var selectedMissingShot: GalleryIndexEntry? {
    guard let selectedLibraryPath else { return displayedMissingShots.first }
    return missingShots.first { $0.path == selectedLibraryPath }
  }

  var cleanupActivePaths: Set<String> {
    Set(ShotQueueStore.shared.items.map(\.path))
  }

  func bootstrap() {
#if DEBUG
    if configureUITestScenarioIfNeeded() { return }
#endif
    loadLibrary()
  }

#if DEBUG
  private func configureUITestScenarioIfNeeded() -> Bool {
    let arguments = ProcessInfo.processInfo.arguments
    guard let flagIndex = arguments.firstIndex(of: "--ui-test-scenario"),
          arguments.indices.contains(flagIndex + 1) else { return false }

    let scenario = arguments[flagIndex + 1]
    status = nil
    isBusy = false
    searchText = ""
    ShotQueueStore.shared.clearAll()
    EditorDraftStore.shared.clear()

    switch scenario {
    case "permission":
      mode = .permissionRequired
    case "error":
      mode = .error(localized("status.capture_failed"))
    case "review", "editor":
      let item = ShotQueueStore.shared.enqueue(path: Self.makeUITestImage().path)
      selectedSection = .currentSession
      if scenario == "review" {
        mode = .captureReview(item.id)
      } else {
        mode = .editor(item.id)
        EditorDraftStore.shared.recordAnnotations([], cropRect: CGRect(x: 0, y: 0, width: 0.8, height: 0.8), for: item.id)
      }
    default:
      let url = Self.makeUITestImage()
      let entry = GalleryIndexEntry(
        path: url.path,
        fileName: url.lastPathComponent,
        tags: ["ui-test"],
        lastKnownCreatedAt: Date(),
        lastSeenAt: Date()
      )
      libraryShots = [LibraryShot(id: url.path, path: url.path, createdAt: Date(), entry: entry)]
      SettingsStore.shared.gallerySearchIndexEnabled = false
      selectedLibraryPath = nil
      selectedSection = .library
      mode = .library
    }
    return true
  }

  private static func makeUITestImage() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("QPARK UI Test.png")
    guard !FileManager.default.fileExists(atPath: url.path) else { return url }
    let image = NSImage(size: NSSize(width: 640, height: 360))
    image.lockFocus()
    NSColor.windowBackgroundColor.setFill()
    NSRect(x: 0, y: 0, width: 640, height: 360).fill()
    NSColor.systemCyan.setFill()
    NSBezierPath(roundedRect: NSRect(x: 64, y: 80, width: 512, height: 200), xRadius: 24, yRadius: 24).fill()
    image.unlockFocus()
    if let data = ExportService.shared.pngData(from: image) {
      try? data.write(to: url, options: .atomic)
    }
    return url
  }
#endif

  func presentStatus(
    _ message: String,
    kind: WorkspaceStatusKind = .info,
    autoDismiss: Bool = true
  ) {
    statusDismissTask?.cancel()
    status = WorkspaceStatus(kind: kind, message: message)
    if let app = NSApp {
      NSAccessibility.post(
        element: app,
        notification: .announcementRequested,
        userInfo: [
          .announcement: message,
          .priority: NSAccessibilityPriorityLevel.high.rawValue
        ]
      )
    }
    guard autoDismiss else { return }
    let statusID = status?.id
    statusDismissTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled, self?.status?.id == statusID else { return }
      self?.status = nil
    }
  }

  func showLibrary() {
    selectedSection = .library
    mode = .library
    loadLibrary()
  }

  func showCurrentSession() {
    showSessionOverview()
  }

  func showSessionOverview() {
    selectedSection = .currentSession
    mode = .library
  }

  func showPermissionRequired() {
    mode = .permissionRequired
    presentStatus(localized("permission.title"), kind: .warning, autoDismiss: false)
  }

  func showError(_ keyOrMessage: String) {
    mode = .error(keyOrMessage)
    presentStatus(keyOrMessage, kind: .error, autoDismiss: false)
  }

  func captured(path: String) {
    let item = ShotQueueStore.shared.enqueue(path: path)
    selectedSection = .currentSession
    presentStatus(localized("review.captured"), kind: .success)
    if SettingsStore.shared.defaultQuickAction == "edit" {
      openEditor(itemID: item.id)
    } else {
      showCaptureReview(itemID: item.id)
    }
  }

  func openEditor(itemID: UUID) {
    selectedSection = .currentSession
    ShotQueueStore.shared.activeID = itemID
    mode = .editor(itemID)
  }

  func openEditor(forPath path: String) {
    let item = ShotQueueStore.shared.enqueue(path: path)
    openEditor(itemID: item.id)
  }

  func showCaptureReview(itemID: UUID) {
    selectedSection = .currentSession
    ShotQueueStore.shared.activeID = itemID
    mode = .captureReview(itemID)
  }

  func selectLibraryShot(_ shot: LibraryShot) {
    selectedLibraryPath = shot.path
    mode = .library
  }

  func selectMissingShot(_ shot: GalleryIndexEntry) {
    selectedLibraryPath = shot.path
    selectedSection = .missing
    mode = .library
  }

  func toggleFavorite(path: String) {
    galleryIndex.toggleFavorite(path: path)
    loadLibrary()
  }

  func updateTags(path: String, text: String) {
    let tags = text.split(separator: ",").map(String.init)
    galleryIndex.setTags(tags, for: path)
    refreshIndexBackedState()
  }

  func moveLibraryShotToTrash(path: String) {
    let url = URL(fileURLWithPath: path)
    let bookmarkData = galleryIndex.bookmarkData(for: path)
    isBusy = true
    DispatchQueue.global(qos: .userInitiated).async {
      let access = securityScopedAccess(url: url, bookmarkData: bookmarkData)
      defer { access.stop() }
      do {
        var resultURL: NSURL?
        try FileManager.default.trashItem(at: access.url, resultingItemURL: &resultURL)
        DispatchQueue.main.async {
          self.galleryIndex.forget(path: path)
          if self.selectedLibraryPath == path {
            self.selectedLibraryPath = nil
          }
          self.isBusy = false
          self.presentStatus(localized("status.moved_to_trash"), kind: .success)
          self.loadLibrary()
        }
      } catch {
        DispatchQueue.main.async {
          self.isBusy = false
          self.presentStatus(localized("status.delete_failed"), kind: .error)
        }
      }
    }
  }

  /// Compatibility bridge for the former destructive API.
  func deleteLibraryShot(path: String) {
    moveLibraryShotToTrash(path: path)
  }

  func forgetMissing(path: String) {
    galleryIndex.forget(path: path)
    if selectedLibraryPath == path {
      selectedLibraryPath = nil
    }
    refreshIndexBackedState()
    presentStatus(localized("status.missing_forgotten"), kind: .success)
  }

  func relinkMissing(from oldPath: String, to newURL: URL, bookmarkData: Data?) {
    guard Self.isSupportedImage(newURL) else {
      presentStatus(localized("status.unsupported_image"), kind: .error)
      return
    }

    let access = securityScopedAccess(url: newURL, bookmarkData: bookmarkData)
    defer { access.stop() }
    guard loadImageForRendering(path: access.url.path) != nil else {
      presentStatus(localized("status.unsupported_image"), kind: .error)
      return
    }
    let values = try? access.url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
    let createdAt = values?.creationDate ?? values?.contentModificationDate ?? Date()
    guard galleryIndex.relink(
      from: oldPath,
      to: access.url,
      createdAt: createdAt,
      bookmarkData: bookmarkData
    ) != nil else {
      presentStatus(localized("status.relink_failed"), kind: .error)
      return
    }
    selectedLibraryPath = access.url.path
    selectedSection = .library
    presentStatus(localized("status.relinked"), kind: .success)
    loadLibrary()
  }

  func loadLibrary() {
    let requestID = UUID()
    loadRequestID = requestID
    let saveDirectory = SettingsStore.shared.saveDirectory
    let saveDirectoryBookmarkData = SettingsStore.shared.saveDirectoryBookmarkData
    let folderCandidates = Self.galleryFolderCandidates(
      saveDirectory: saveDirectory,
      bookmarkData: saveDirectoryBookmarkData,
      fileManager: fileManager
    )
    let indexedEntries = Array(galleryIndex.entries.values)
    isBusy = true

    DispatchQueue.global(qos: .userInitiated).async {
      let fileManager = FileManager.default
      var snapshotsByPath: [String: GalleryFileSnapshot] = [:]

      for folderCandidate in folderCandidates {
        let access = securityScopedAccess(
          url: folderCandidate.url,
          bookmarkData: folderCandidate.bookmarkData
        )
        defer { access.stop() }
        let contents = (try? fileManager.contentsOfDirectory(
          at: access.url,
          includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
          options: .skipsHiddenFiles
        )) ?? []
        for url in contents where Self.isSupportedImage(url) {
          let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
          let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
          snapshotsByPath[url.path] = GalleryFileSnapshot(path: url.path, createdAt: date)
        }
      }

      // A user may relink a missing item outside the configured gallery root.
      // Its security-scoped bookmark keeps the file available across launches.
      for entry in indexedEntries where snapshotsByPath[entry.path] == nil {
        let url = URL(fileURLWithPath: entry.path)
        let access = securityScopedAccess(url: url, bookmarkData: entry.securityBookmarkData)
        defer { access.stop() }
        guard fileManager.fileExists(atPath: access.url.path), Self.isSupportedImage(access.url) else {
          continue
        }
        let values = try? access.url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let date = values?.creationDate
          ?? values?.contentModificationDate
          ?? entry.lastKnownCreatedAt
          ?? .distantPast
        snapshotsByPath[access.url.path] = GalleryFileSnapshot(path: access.url.path, createdAt: date)
      }

      let snapshots = snapshotsByPath.values.sorted { $0.createdAt > $1.createdAt }
      DispatchQueue.main.async {
        guard self.loadRequestID == requestID else { return }
        self.galleryIndex.reconcile(existingFiles: snapshots)
        self.libraryShots = snapshots.map {
          LibraryShot(
            id: $0.path,
            path: $0.path,
            createdAt: $0.createdAt,
            entry: self.galleryIndex.entry(for: $0.path)
          )
        }
        self.missingShots = self.galleryIndex.missingEntries
        let availablePaths = Set(self.libraryShots.map(\.path) + self.missingShots.map(\.path))
        if let selected = self.selectedLibraryPath, !availablePaths.contains(selected) {
          self.selectedLibraryPath = self.displayedLibraryShots.first?.path
        } else if self.selectedLibraryPath == nil {
          self.selectedLibraryPath = self.selectedSection == .missing
            ? self.missingShots.first?.path
            : self.displayedLibraryShots.first?.path
        }
        self.isBusy = false
        self.scheduleOCR(for: snapshots.map(\.path))
      }
    }
  }

  func copyFinalImage(path: String, completion: ((Bool) -> Void)? = nil) {
    DispatchQueue.global(qos: .userInitiated).async {
      let image = loadImageForRendering(path: path)
      DispatchQueue.main.async {
        guard let image else {
          self.presentStatus(localized("status.copy_failed"), kind: .error)
          completion?(false)
          return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        self.presentStatus(localized("review.copied"), kind: .success)
        completion?(true)
      }
    }
  }

  func share(path: String) {
    let picker = NSSharingServicePicker(items: [URL(fileURLWithPath: path)])
    if let window = NSApp.keyWindow, let contentView = window.contentView {
      let rect = NSRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
      picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
    }
  }

  func pin(path: String) {
    PinnedShotWindowController.shared.pinImage(at: path)
    presentStatus(localized("review.pinned"), kind: .success)
  }

  static func galleryFolderURL(saveDirectory: String, fileManager: FileManager = .default) -> URL {
    galleryFolderURLs(saveDirectory: saveDirectory, fileManager: fileManager)[0]
  }

  static func galleryFolderURLs(saveDirectory: String, fileManager: FileManager = .default) -> [URL] {
    galleryFolderCandidates(
      saveDirectory: saveDirectory,
      bookmarkData: nil,
      fileManager: fileManager
    ).map(\.url)
  }

  static func galleryFolderCandidates(
    saveDirectory: String,
    bookmarkData: Data?,
    fileManager: FileManager = .default
  ) -> [StorageFolderCandidate] {
    galleryStorageFolderCandidates(
      saveDirectory: saveDirectory,
      bookmarkData: bookmarkData,
      fileManager: fileManager
    )
  }

  private func refreshIndexBackedState() {
    libraryShots = libraryShots.map { shot in
      LibraryShot(
        id: shot.id,
        path: shot.path,
        createdAt: shot.createdAt,
        entry: galleryIndex.entry(for: shot.path)
      )
    }
    missingShots = galleryIndex.missingEntries
  }

  private func scheduleOCR(for paths: [String]) {
    guard SettingsStore.shared.galleryOCREnabled else { return }
    let languageSignature = OCRService.languageSignature(
      for: SettingsStore.shared.textRecognitionLanguageCodes
    )
    for path in paths.prefix(40) {
      let value = galleryIndex.entry(for: path)
      let needsOCR = value.ocrIndexedAt == nil
        || value.ocrLanguageSignature != languageSignature
        || value.ocrEngineVersion != OCRService.indexVersion
      guard needsOCR, !runningOCRPaths.contains(path) else { continue }
      runningOCRPaths.insert(path)
      OCRService.shared.recognize(in: path) { result in
        self.runningOCRPaths.remove(path)
        guard self.libraryShots.contains(where: { $0.path == path }) else { return }
        switch result {
        case .succeeded(let text):
          self.galleryIndex.updateOCRText(
            text,
            for: path,
            languageSignature: languageSignature,
            engineVersion: OCRService.indexVersion
          )
        case .noText, .failed:
          self.galleryIndex.updateOCRText(
            "",
            for: path,
            languageSignature: languageSignature,
            engineVersion: OCRService.indexVersion
          )
        }
        self.refreshIndexBackedState()
      }
    }
  }

  func isOCRRunning(for path: String) -> Bool {
    runningOCRPaths.contains(path)
  }

  private func filterFilenames(_ paths: [String], query: String) -> [String] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return paths }
    return paths.filter {
      URL(fileURLWithPath: $0).lastPathComponent.lowercased().contains(normalized)
    }
  }

  nonisolated private static func isSupportedImage(_ url: URL) -> Bool {
    guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
    return type.conforms(to: .image)
  }
}
