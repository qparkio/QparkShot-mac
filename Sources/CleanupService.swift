import Foundation

actor CleanupService {
  typealias TrashOperation = @Sendable (URL) throws -> Void
  typealias MutationGuard = @MainActor @Sendable (URL, Bool) -> Bool

  static let shared = CleanupService()

  private let fileManager: FileManager
  private let trashOperation: TrashOperation
  private let beforeMutation: (@Sendable (URL) -> Void)?

  init(
    fileManager: FileManager = .default,
    trashOperation: TrashOperation? = nil,
    beforeMutation: (@Sendable (URL) -> Void)? = nil
  ) {
    self.fileManager = fileManager
    self.beforeMutation = beforeMutation
    self.trashOperation = trashOperation ?? { url in
      var resultingURL: NSURL?
      try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
    }
  }

  func run(
    policy: CleanupPolicy,
    galleryEntries: [GalleryIndexEntry],
    activePaths: Set<String>,
    temporaryRoots: [URL],
    savedRoots: [StorageFolderCandidate],
    now: Date = Date(),
    allowsMutation: MutationGuard? = nil
  ) async -> CleanupReport {
    guard policy.mode == .afterDuration else { return CleanupReport() }

    let cutoff = now.addingTimeInterval(-max(policy.maxAge, 60))
    let activeCanonicalPaths = Set(activePaths.map(canonicalPath))
    var report = CleanupReport()

    for root in temporaryRoots {
      await cleanTemporaryRoot(
        root,
        cutoff: cutoff,
        activeCanonicalPaths: activeCanonicalPaths,
        allowsMutation: allowsMutation,
        report: &report
      )
    }

    if policy.includeSavedFiles {
      await cleanSavedFiles(
        galleryEntries,
        roots: savedRoots,
        cutoff: cutoff,
        activeCanonicalPaths: activeCanonicalPaths,
        allowsMutation: allowsMutation,
        report: &report
      )
    }

    return report
  }

  private func cleanTemporaryRoot(
    _ root: URL,
    cutoff: Date,
    activeCanonicalPaths: Set<String>,
    allowsMutation: MutationGuard?,
    report: inout CleanupReport
  ) async {
    let canonicalRoot = canonicalPath(root)
    guard fileManager.fileExists(atPath: canonicalRoot) else { return }

    let keys: [URLResourceKey] = [
      .isRegularFileKey,
      .contentModificationDateKey,
      .creationDateKey
    ]
    guard let enumerator = fileManager.enumerator(
      at: root,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
      return
    }

    while let fileURL = enumerator.nextObject() as? URL {
      let canonicalFile = canonicalPath(fileURL)
      guard isDescendant(canonicalFile, of: canonicalRoot),
            !activeCanonicalPaths.contains(canonicalFile),
            isOldRegularFile(fileURL, cutoff: cutoff) else {
        continue
      }

      // Recheck immediately before mutation so a file refreshed by an export
      // between enumeration and deletion is preserved.
      beforeMutation?(fileURL)
      guard isSafeTemporaryCandidate(
        fileURL,
        root: canonicalRoot,
        cutoff: cutoff,
        activeCanonicalPaths: activeCanonicalPaths
      ) else { continue }
      do {
        let removed = try await MainActor.run {
          guard allowsMutation?(fileURL, false) ?? true,
                self.isSafeTemporaryCandidate(fileURL, root: canonicalRoot, cutoff: cutoff, activeCanonicalPaths: activeCanonicalPaths) else { return false }
          try FileManager.default.removeItem(at: fileURL)
          return true
        }
        if removed { report.deletedTemporaryPaths.append(fileURL.path) }
      } catch {
        report.failures.append(fileURL.path)
      }
    }
  }

  private func cleanSavedFiles(
    _ entries: [GalleryIndexEntry],
    roots: [StorageFolderCandidate],
    cutoff: Date,
    activeCanonicalPaths: Set<String>,
    allowsMutation: MutationGuard?,
    report: inout CleanupReport
  ) async {
    let accesses = roots.map {
      securityScopedAccess(url: $0.url, bookmarkData: $0.bookmarkData)
    }
    defer { accesses.forEach { $0.stop() } }
    let canonicalRoots = accesses.map { canonicalPath($0.url) }

    for entry in entries where !entry.isMissing && !entry.favorite {
      let fileURL = URL(fileURLWithPath: entry.path)
      let canonicalFile = canonicalPath(fileURL)
      guard canonicalRoots.contains(where: { isDescendant(canonicalFile, of: $0) }),
            !activeCanonicalPaths.contains(canonicalFile),
            isOldRegularFile(fileURL, cutoff: cutoff) else {
        continue
      }

      beforeMutation?(fileURL)
      guard isSafeSavedCandidate(
        fileURL,
        roots: canonicalRoots,
        cutoff: cutoff,
        activeCanonicalPaths: activeCanonicalPaths
      ) else { continue }
      do {
        let trash = trashOperation
        let removed = try await MainActor.run {
          guard allowsMutation?(fileURL, true) ?? true,
                self.isSafeSavedCandidate(fileURL, roots: canonicalRoots, cutoff: cutoff, activeCanonicalPaths: activeCanonicalPaths) else { return false }
          try trash(fileURL)
          return true
        }
        if removed { report.trashedSavedPaths.append(entry.path) }
      } catch {
        report.failures.append(entry.path)
      }
    }
  }

  nonisolated private func isOldRegularFile(_ url: URL, cutoff: Date) -> Bool {
    // Recreate the URL so resource values cached by FileManager's enumerator
    // cannot hide a concurrent writer's latest modification date.
    let freshURL = URL(fileURLWithPath: url.path)
    guard let values = try? freshURL.resourceValues(forKeys: [
      .isRegularFileKey,
      .contentModificationDateKey,
      .creationDateKey
    ]),
    values.isRegularFile == true else {
      return false
    }
    let date = values.contentModificationDate ?? values.creationDate ?? .distantFuture
    return date < cutoff
  }

  nonisolated private func isSafeTemporaryCandidate(
    _ url: URL,
    root: String,
    cutoff: Date,
    activeCanonicalPaths: Set<String>
  ) -> Bool {
    let candidate = canonicalPath(url)
    return isDescendant(candidate, of: root)
      && !activeCanonicalPaths.contains(candidate)
      && isOldRegularFile(url, cutoff: cutoff)
  }

  nonisolated private func isSafeSavedCandidate(
    _ url: URL,
    roots: [String],
    cutoff: Date,
    activeCanonicalPaths: Set<String>
  ) -> Bool {
    let candidate = canonicalPath(url)
    return roots.contains(where: { isDescendant(candidate, of: $0) })
      && !activeCanonicalPaths.contains(candidate)
      && isOldRegularFile(url, cutoff: cutoff)
  }

  nonisolated private func canonicalPath(_ url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
  }

  nonisolated private func canonicalPath(_ path: String) -> String {
    canonicalPath(URL(fileURLWithPath: path))
  }

  nonisolated private func isDescendant(_ path: String, of root: String) -> Bool {
    path == root || path.hasPrefix(root + "/")
  }
}
