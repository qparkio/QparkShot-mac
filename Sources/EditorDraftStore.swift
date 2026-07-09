import Combine
import Foundation

struct EditorDraft: Equatable {
  var annotations: [Annotation] = []
  var cropRect: CGRect? = nil
  var undoStack: [[Annotation]] = [[]]
  var redoStack: [[Annotation]] = []
  var isDirty: Bool = false
  var updatedAt: Date = Date()
}

final class EditorDraftStore: ObservableObject {
  static let shared = EditorDraftStore()

  @Published private(set) var drafts: [UUID: EditorDraft] = [:]

  private init() {}

  func draft(for itemID: UUID) -> EditorDraft {
    if let draft = drafts[itemID] {
      return draft
    }
    let draft = EditorDraft()
    drafts[itemID] = draft
    return draft
  }

  func update(_ itemID: UUID, _ mutate: (inout EditorDraft) -> Void) {
    var draft = self.draft(for: itemID)
    mutate(&draft)
    draft.updatedAt = Date()
    drafts[itemID] = draft
  }

  func recordAnnotations(_ annotations: [Annotation], cropRect: CGRect?, for itemID: UUID) {
    update(itemID) { draft in
      if draft.undoStack.last != annotations {
        draft.undoStack.append(annotations)
      }
      draft.annotations = annotations
      draft.cropRect = cropRect
      draft.redoStack.removeAll()
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
