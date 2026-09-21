import Combine
import Foundation

struct EditorSnapshot: Equatable {
  var annotations: [Annotation] = []
  var cropRect: CGRect? = nil
}

struct EditorDraft: Equatable {
  var annotations: [Annotation] = []
  var cropRect: CGRect? = nil
  var undoStack: [EditorSnapshot] = [EditorSnapshot()]
  var redoStack: [EditorSnapshot] = []
  var isDirty: Bool = false
  var updatedAt: Date = Date()
}

final class EditorDraftStore: ObservableObject {
  static let shared = EditorDraftStore()

  @Published private(set) var drafts: [UUID: EditorDraft] = [:]

  init() {}

  func draft(for itemID: UUID) -> EditorDraft {
    drafts[itemID] ?? EditorDraft()
  }

  func update(_ itemID: UUID, _ mutate: (inout EditorDraft) -> Void) {
    var draft = self.draft(for: itemID)
    mutate(&draft)
    draft.updatedAt = Date()
    drafts[itemID] = draft
  }

  func recordAnnotations(_ annotations: [Annotation], cropRect: CGRect?, for itemID: UUID) {
    update(itemID) { draft in
      let snapshot = EditorSnapshot(annotations: annotations, cropRect: cropRect)
      guard draft.undoStack.last != snapshot else { return }
      draft.undoStack.append(snapshot)
      draft.annotations = annotations
      draft.cropRect = cropRect
      draft.redoStack.removeAll()
      draft.isDirty = true
    }
  }

  func undo(_ itemID: UUID) {
    update(itemID) { draft in
      guard draft.undoStack.count > 1 else { return }
      draft.redoStack.append(draft.undoStack.removeLast())
      let previous = draft.undoStack.last!
      draft.annotations = previous.annotations
      draft.cropRect = previous.cropRect
      draft.isDirty = true
    }
  }

  func redo(_ itemID: UUID) {
    update(itemID) { draft in
      guard let next = draft.redoStack.popLast() else { return }
      draft.undoStack.append(next)
      draft.annotations = next.annotations
      draft.cropRect = next.cropRect
      draft.isDirty = true
    }
  }

  func markSaved(_ itemID: UUID) {
    update(itemID) { draft in
      draft.isDirty = false
    }
  }

  func remove(_ itemID: UUID) {
    drafts.removeValue(forKey: itemID)
  }

  func clear() {
    drafts.removeAll()
  }
}
