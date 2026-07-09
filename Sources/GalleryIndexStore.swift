import Combine
import Foundation

struct GalleryFileSnapshot: Equatable {
  let path: String
  let createdAt: Date
}

struct GalleryIndexEntry: Codable, Equatable, Identifiable {
  var path: String
  var fileName: String
  var favorite: Bool
  var tags: [String]
  var ocrText: String
  var updatedAt: Date
  var ocrIndexedAt: Date?
  var ocrLanguageSignature: String?
  var ocrEngineVersion: Int?
  var lastKnownCreatedAt: Date?
  var lastSeenAt: Date?
  var missingSince: Date?
  var securityBookmarkData: Data?

  var id: String { path }
  var isMissing: Bool { missingSince != nil }

  init(
    path: String,
    fileName: String,
    favorite: Bool = false,
    tags: [String] = [],
    ocrText: String = "",
    updatedAt: Date = Date(),
    ocrIndexedAt: Date? = nil,
    ocrLanguageSignature: String? = nil,
    ocrEngineVersion: Int? = nil,
    lastKnownCreatedAt: Date? = nil,
    lastSeenAt: Date? = nil,
    missingSince: Date? = nil,
    securityBookmarkData: Data? = nil
  ) {
    self.path = path
    self.fileName = fileName
    self.favorite = favorite
    self.tags = tags
    self.ocrText = ocrText
    self.updatedAt = updatedAt
    self.ocrIndexedAt = ocrIndexedAt
    self.ocrLanguageSignature = ocrLanguageSignature
    self.ocrEngineVersion = ocrEngineVersion
    self.lastKnownCreatedAt = lastKnownCreatedAt
    self.lastSeenAt = lastSeenAt
    self.missingSince = missingSince
    self.securityBookmarkData = securityBookmarkData
  }
}

final class GalleryIndexStore: ObservableObject {
  static let shared = GalleryIndexStore()

  @Published private(set) var entries: [String: GalleryIndexEntry] = [:]

  private let defaults: UserDefaults
  private let key = "qpark_shot.gallery_index.v1"
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    load()
  }

  var existingEntries: [GalleryIndexEntry] {
    entries.values.filter { !$0.isMissing }
  }

  var missingEntries: [GalleryIndexEntry] {
    entries.values
      .filter(\.isMissing)
      .sorted {
        ($0.missingSince ?? .distantPast) > ($1.missingSince ?? .distantPast)
      }
  }

  func entry(for path: String) -> GalleryIndexEntry {
    if let entry = entries[path] {
      return entry
    }
    return GalleryIndexEntry(
      path: path,
      fileName: URL(fileURLWithPath: path).lastPathComponent
    )
  }

  func bookmarkData(for path: String) -> Data? {
    entries[path]?.securityBookmarkData
  }

  /// Reconciles the persisted index without discarding metadata for files that
  /// disappeared outside the app. Those records power the Missing section.
  func reconcile(existingFiles: [GalleryFileSnapshot], now: Date = Date()) {
    let snapshotsByPath = Dictionary(
      existingFiles.map { ($0.path, $0) },
      uniquingKeysWith: { first, _ in first }
    )

    for (path, snapshot) in snapshotsByPath {
      var value = entry(for: path)
      value.path = path
      value.fileName = URL(fileURLWithPath: path).lastPathComponent
      value.lastKnownCreatedAt = snapshot.createdAt
      value.lastSeenAt = now
      value.missingSince = nil
      entries[path] = value
    }

    for path in entries.keys where snapshotsByPath[path] == nil {
      guard var value = entries[path], value.missingSince == nil else { continue }
      value.missingSince = now
      value.updatedAt = now
      entries[path] = value
    }

    save()
  }

  /// Compatibility bridge for older call sites and tests.
  func updateExistingPaths(_ paths: [String]) {
    reconcile(
      existingFiles: paths.map {
        GalleryFileSnapshot(path: $0, createdAt: entry(for: $0).lastKnownCreatedAt ?? Date())
      }
    )
  }

  @discardableResult
  func relink(
    from oldPath: String,
    to newURL: URL,
    createdAt: Date,
    bookmarkData: Data?,
    now: Date = Date()
  ) -> GalleryIndexEntry? {
    guard var value = entries.removeValue(forKey: oldPath) else { return nil }
    value.path = newURL.path
    value.fileName = newURL.lastPathComponent
    value.lastKnownCreatedAt = createdAt
    value.lastSeenAt = now
    value.missingSince = nil
    value.securityBookmarkData = bookmarkData
    value.updatedAt = now
    entries[newURL.path] = value
    save()
    return value
  }

  func forget(path: String) {
    entries.removeValue(forKey: path)
    save()
  }

  func remove(path: String) {
    forget(path: path)
  }

  func toggleFavorite(path: String) {
    var value = entry(for: path)
    value.favorite.toggle()
    value.updatedAt = Date()
    entries[path] = value
    save()
  }

  func setTags(_ tags: [String], for path: String) {
    var value = entry(for: path)
    value.tags = tags
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .reduce(into: []) { result, tag in
        if !result.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
          result.append(tag)
        }
      }
    value.updatedAt = Date()
    entries[path] = value
    save()
  }

  func updateOCRText(
    _ text: String,
    for path: String,
    languageSignature: String? = nil,
    engineVersion: Int? = nil
  ) {
    var value = entry(for: path)
    value.ocrText = text
    value.ocrIndexedAt = Date()
    value.ocrLanguageSignature = languageSignature
    value.ocrEngineVersion = engineVersion
    value.updatedAt = Date()
    entries[path] = value
    save()
  }

  func pathsMatching(_ query: String, in paths: [String]) -> [String] {
    let tokens = query
      .lowercased()
      .split(whereSeparator: { $0.isWhitespace })
      .map(String.init)

    guard !tokens.isEmpty else { return paths }

    return paths.filter { path in
      let value = entry(for: path)
      let haystack = ([value.fileName, value.ocrText] + value.tags)
        .joined(separator: " ")
        .lowercased()
      return tokens.allSatisfy { haystack.contains($0) }
    }
  }

  func pathsWithFavoritesFirst(_ paths: [String]) -> [String] {
    let originalOrder = Dictionary(
      uniqueKeysWithValues: paths.enumerated().map { ($0.element, $0.offset) }
    )
    return paths.sorted { lhs, rhs in
      let leftFavorite = entry(for: lhs).favorite
      let rightFavorite = entry(for: rhs).favorite
      if leftFavorite != rightFavorite {
        return leftFavorite && !rightFavorite
      }
      return (originalOrder[lhs] ?? 0) < (originalOrder[rhs] ?? 0)
    }
  }

  private func load() {
    guard let data = defaults.data(forKey: key),
          let decoded = try? decoder.decode([String: GalleryIndexEntry].self, from: data) else {
      entries = [:]
      return
    }
    entries = decoded
  }

  private func save() {
    guard let data = try? encoder.encode(entries) else { return }
    defaults.set(data, forKey: key)
  }
}
