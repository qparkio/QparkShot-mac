import Combine
import Foundation

struct ShotQueueItem: Identifiable, Equatable {
  let id: UUID
  let path: String
  let capturedAt: Date
}

final class ShotQueueStore: ObservableObject {
  static let shared = ShotQueueStore()

  @Published private(set) var items: [ShotQueueItem] = []
  @Published var activeID: UUID? = nil

  private init() {}

  @discardableResult
  func enqueue(path: String, capturedAt: Date = Date()) -> ShotQueueItem {
    if let existing = items.first(where: { $0.path == path }) {
      activeID = existing.id
      return existing
    }

    let item = ShotQueueItem(id: UUID(), path: path, capturedAt: capturedAt)
    items.append(item)
    activeID = item.id
    return item
  }

  func item(for id: UUID) -> ShotQueueItem? {
    items.first { $0.id == id }
  }

  func item(forPath path: String) -> ShotQueueItem? {
    items.first { $0.path == path }
  }

  @discardableResult
  func remove(_ id: UUID) -> UUID? {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return activeID }
    let removed = items.remove(at: index)

    if isTemporaryShot(path: removed.path) {
      try? FileManager.default.removeItem(atPath: removed.path)
    }

    if activeID == id {
      activeID = items.isEmpty ? nil : items[min(index, items.count - 1)].id
    }

    return activeID
  }

  func clearAll() {
    for item in items where isTemporaryShot(path: item.path) {
      try? FileManager.default.removeItem(atPath: item.path)
    }

    items.removeAll()
    activeID = nil
  }

  var temporaryItemCount: Int {
    items.filter { isTemporaryShot(path: $0.path) }.count
  }

  func isTemporaryShot(path: String) -> Bool {
    let candidate = URL(fileURLWithPath: path)
      .standardizedFileURL
      .resolvingSymlinksInPath()
      .path
    return [captureScratchFolderURL(), storageFolderURL(isTemporary: true)].contains { rootURL in
      let root = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
      return candidate == root || candidate.hasPrefix(root + "/")
    }
  }
}
