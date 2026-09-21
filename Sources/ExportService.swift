import AppKit
import Foundation
import OSLog

struct ExportPreset: Codable, Equatable, Identifiable {
  let id: String
  let name: String
  let filenameToken: String
  let includesWatermark: Bool

  static let clean = ExportPreset(
    id: "clean",
    name: "Clean PNG",
    filenameToken: "clean",
    includesWatermark: false
  )

  static let watermarked = ExportPreset(
    id: "watermarked",
    name: "Watermarked",
    filenameToken: "watermarked",
    includesWatermark: true
  )

  static let support = ExportPreset(
    id: "support",
    name: "For Support",
    filenameToken: "support",
    includesWatermark: true
  )

  static let all: [ExportPreset] = [.clean, .watermarked, .support]

  static func preset(for id: String) -> ExportPreset {
    all.first { $0.id == id } ?? .watermarked
  }
}

struct ExportContext {
  var image: NSImage
  var annotations: [Annotation]
  var cropRect: CGRect?
  var preset: ExportPreset
  var watermark: WatermarkRenderSettings
}

enum FileNameTemplate {
  static func makeFilename(
    template: String,
    preset: ExportPreset,
    date: Date = Date(),
    uuid: String = String(UUID().uuidString.prefix(8))
  ) -> String {
    let template = template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "{date}_{time}_{preset}"
      : template

    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.dateFormat = "yyyyMMdd"

    let timeFormatter = DateFormatter()
    timeFormatter.locale = Locale(identifier: "en_US_POSIX")
    timeFormatter.dateFormat = "HHmmss_SSS"

    let raw = template
      .replacingOccurrences(of: "{date}", with: dateFormatter.string(from: date))
      .replacingOccurrences(of: "{time}", with: timeFormatter.string(from: date))
      .replacingOccurrences(of: "{preset}", with: preset.filenameToken)
      .replacingOccurrences(of: "{uuid}", with: uuid)

    let cleaned = raw
      .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
      .joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return cleaned.isEmpty ? "Screenshot_\(uuid)" : cleaned
  }
}

final class ExportService {
  static let shared = ExportService()

  private let imageEncodingLock = NSLock()
  private let exportWriteLock = NSLock()
  private let logger = Logger(subsystem: "com.qpark.shot", category: "export")

  private init() {}

  func render(_ context: ExportContext) -> NSImage? {
    let watermark = context.preset.includesWatermark
      ? context.watermark
      : WatermarkRenderSettings.disabled

    return renderAnnotatedImage(
      image: context.image,
      annotations: context.annotations,
      cropRect: context.cropRect,
      watermark: watermark
    )
  }

  func save(
    image: NSImage,
    isTemporary: Bool,
    preset: ExportPreset,
    filenameTemplate: String,
    fileManager: FileManager = .default
  ) -> String? {
    guard let pngData = pngData(from: image) else { return nil }
    return save(
      pngData: pngData,
      isTemporary: isTemporary,
      preset: preset,
      filenameTemplate: filenameTemplate,
      fileManager: fileManager
    )
  }

  func save(
    pngData: Data,
    isTemporary: Bool,
    preset: ExportPreset,
    filenameTemplate: String,
    fileManager: FileManager = .default
  ) -> String? {
    let folderCandidates = storageFolderCandidates(isTemporary: isTemporary, fileManager: fileManager)
    for folderCandidate in folderCandidates {
      let access = securityScopedAccess(
        url: folderCandidate.url,
        bookmarkData: folderCandidate.bookmarkData
      )
      defer { access.stop() }
      if let path = save(
        pngData: pngData,
        in: access.url,
        preset: preset,
        filenameTemplate: filenameTemplate,
        fileManager: fileManager
      ) {
        return path
      }
    }
    return nil
  }

  private func save(
    pngData: Data,
    in folderURL: URL,
    preset: ExportPreset,
    filenameTemplate: String,
    fileManager: FileManager
  ) -> String? {
    do {
      try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

      exportWriteLock.lock()
      defer { exportWriteLock.unlock() }

      for _ in 0..<20 {
        let fileURL = uniqueExportURL(
          in: folderURL,
          preset: preset,
          filenameTemplate: filenameTemplate,
          fileManager: fileManager
        )
        do {
          try pngData.write(to: fileURL, options: [.atomic])
          return fileURL.path
        } catch {
          if fileManager.fileExists(atPath: fileURL.path) {
            continue
          }
          logger.error("Export write failed at \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
          return nil
        }
      }
      return nil
    } catch {
      logger.error("Export folder unavailable at \(folderURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  func save(
    context: ExportContext,
    isTemporary: Bool,
    filenameTemplate: String
  ) -> String? {
    guard let image = render(context) else { return nil }
    return save(
      image: image,
      isTemporary: isTemporary,
      preset: context.preset,
      filenameTemplate: filenameTemplate
    )
  }

  func pngData(from image: NSImage) -> Data? {
    imageEncodingLock.lock()
    defer { imageEncodingLock.unlock() }

    if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
      let rep = NSBitmapImageRep(cgImage: cgImage)
      rep.size = image.size
      return rep.representation(using: .png, properties: [:])
    }

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
      return nil
    }
    return rep.representation(using: .png, properties: [:])
  }

  private func uniqueExportURL(
    in folderURL: URL,
    preset: ExportPreset,
    filenameTemplate: String,
    fileManager: FileManager
  ) -> URL {
    let baseName = FileNameTemplate.makeFilename(
      template: filenameTemplate,
      preset: preset
    )

    for attempt in 0..<10 {
      let suffix = attempt == 0 ? "" : "-\(attempt + 1)"
      let candidate = folderURL.appendingPathComponent("\(baseName)\(suffix).png")
      if !fileManager.fileExists(atPath: candidate.path) {
        return candidate
      }
    }

    return folderURL.appendingPathComponent("\(baseName)-\(UUID().uuidString).png")
  }
}

struct StorageFolderCandidate {
  let url: URL
  let bookmarkData: Data?
}

struct SecurityScopedAccess {
  let url: URL
  private let didStartAccessing: Bool
  private let scopeURL: URL?

  init(url: URL, didStartAccessing: Bool, scopeURL: URL? = nil) {
    self.url = url
    self.didStartAccessing = didStartAccessing
    self.scopeURL = scopeURL
  }

  func stop() {
    if didStartAccessing {
      (scopeURL ?? url).stopAccessingSecurityScopedResource()
    }
  }
}

func securityScopedAccess(url: URL, bookmarkData: Data?) -> SecurityScopedAccess {
  guard let bookmarkData else {
    return SecurityScopedAccess(url: url, didStartAccessing: false)
  }

  var isStale = false
  do {
    let resolvedURL = try URL(
      resolvingBookmarkData: bookmarkData,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
    return SecurityScopedAccess(
      url: resolvedURL,
      didStartAccessing: resolvedURL.startAccessingSecurityScopedResource()
    )
  } catch {
    return SecurityScopedAccess(url: url, didStartAccessing: false)
  }
}

/// A folder bookmark grants access to its descendants, but resolves to the folder itself.
func securityScopedImageAccess(
  url: URL,
  bookmarkData: Data?,
  folders: [StorageFolderCandidate]
) -> SecurityScopedAccess {
  if bookmarkData != nil { return securityScopedAccess(url: url, bookmarkData: bookmarkData) }
  let filePath = url.standardizedFileURL.path
  for folder in folders {
    let root = folder.url.standardizedFileURL.path
    guard filePath.hasPrefix(root + "/"), let bookmark = folder.bookmarkData else { continue }
    var stale = false
    guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
    let relative = String(filePath.dropFirst(root.count + 1))
    return SecurityScopedAccess(
      url: resolved.appendingPathComponent(relative),
      didStartAccessing: resolved.startAccessingSecurityScopedResource(),
      scopeURL: resolved
    )
  }
  return SecurityScopedAccess(url: url, didStartAccessing: false)
}

func storageFolderURL(isTemporary: Bool, fileManager: FileManager = .default) -> URL {
  storageFolderURLs(isTemporary: isTemporary, fileManager: fileManager)[0]
}

func storageFolderURLs(isTemporary: Bool, fileManager: FileManager = .default) -> [URL] {
  storageFolderCandidates(isTemporary: isTemporary, fileManager: fileManager).map(\.url)
}

func storageFolderCandidates(isTemporary: Bool, fileManager: FileManager = .default) -> [StorageFolderCandidate] {
  if isTemporary {
    return [
      StorageFolderCandidate(
        url: (AppTestEnvironment.root ?? fileManager.temporaryDirectory)
          .appendingPathComponent("QPARK Shot", isDirectory: true)
          .appendingPathComponent("Export Scratch", isDirectory: true),
        bookmarkData: nil
      )
    ]
  }

  let saveDirectory = SettingsStore.shared.saveDirectory
  let bookmarkData = SettingsStore.shared.saveDirectoryBookmarkData
  return galleryStorageFolderCandidates(
    saveDirectory: saveDirectory,
    bookmarkData: bookmarkData,
    fileManager: fileManager
  )
}

func galleryStorageFolderURLs(saveDirectory: String, fileManager: FileManager = .default) -> [URL] {
  galleryStorageFolderCandidates(
    saveDirectory: saveDirectory,
    bookmarkData: nil,
    fileManager: fileManager
  ).map(\.url)
}

func galleryStorageFolderCandidates(
  saveDirectory: String,
  bookmarkData: Data?,
  fileManager: FileManager = .default
) -> [StorageFolderCandidate] {
  var candidates: [StorageFolderCandidate] = []

  if !saveDirectory.isEmpty {
    candidates.append(
      StorageFolderCandidate(
        url: URL(fileURLWithPath: saveDirectory, isDirectory: true),
        bookmarkData: bookmarkData
      )
    )
  }

  if let root = AppTestEnvironment.root {
    candidates.append(StorageFolderCandidate(
      url: root.appendingPathComponent("Pictures/QPARK Shot", isDirectory: true), bookmarkData: nil
    ))
    return candidates
  }

  let pictures = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first!
  let picturesGallery = pictures.appendingPathComponent("QPARK Shot", isDirectory: true)
  let containerGallery = fileManager.homeDirectoryForCurrentUser
    .appendingPathComponent("Pictures", isDirectory: true)
    .appendingPathComponent("QPARK Shot", isDirectory: true)

  candidates.append(StorageFolderCandidate(url: picturesGallery, bookmarkData: nil))
  if picturesGallery.standardizedFileURL != containerGallery.standardizedFileURL {
    candidates.append(StorageFolderCandidate(url: containerGallery, bookmarkData: nil))
  }

  return candidates.reduce(into: []) { uniqueCandidates, candidate in
    guard !uniqueCandidates.contains(where: { $0.url.standardizedFileURL == candidate.url.standardizedFileURL }) else {
      return
    }
    uniqueCandidates.append(candidate)
  }
}
