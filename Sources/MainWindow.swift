import Cocoa
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MainWindowNavigation: ObservableObject {
  static let shared = MainWindowNavigation()

  private init() {}

  func showGallery() {
    WorkspaceStore.shared.showLibrary()
  }

  func showSettings() {
    PreferencesWindowController.shared.show()
  }

  func openEditor(itemID: UUID) {
    WorkspaceStore.shared.openEditor(itemID: itemID)
  }

  func showQuickAction(itemID: UUID) {
    WorkspaceStore.shared.showCaptureReview(itemID: itemID)
  }
}

final class MainAppWindow: NSWindow {
  static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("QPARKShotMainWindow")

  private var didInstallRootContent = false

  func installRootContent() {
    guard !didInstallRootContent else { return }
    didInstallRootContent = true

    identifier = Self.mainWindowIdentifier
    isReleasedWhenClosed = false
    minSize = NSSize(width: 920, height: 620)

    let rootView = WorkspaceRootView(store: WorkspaceStore.shared)
    let hostingController = NSHostingController(rootView: rootView)
    let windowFrame = frame
    contentViewController = hostingController
    setFrame(windowFrame, display: true)
    title = localized("app.name")

    titlebarAppearsTransparent = false
    titleVisibility = .visible
    if styleMask.contains(.fullSizeContentView) {
      styleMask.remove(.fullSizeContentView)
    }
    isOpaque = false
    backgroundColor = .clear

    let visualEffectView = NSVisualEffectView()
    visualEffectView.translatesAutoresizingMaskIntoConstraints = false
    visualEffectView.material = .underWindowBackground
    visualEffectView.state = .active
    visualEffectView.blendingMode = .behindWindow

    if let windowContentView = contentView {
      windowContentView.addSubview(visualEffectView, positioned: .below, relativeTo: hostingController.view)
      NSLayoutConstraint.activate([
        visualEffectView.leadingAnchor.constraint(equalTo: windowContentView.leadingAnchor),
        visualEffectView.trailingAnchor.constraint(equalTo: windowContentView.trailingAnchor),
        visualEffectView.topAnchor.constraint(equalTo: windowContentView.topAnchor),
        visualEffectView.bottomAnchor.constraint(equalTo: windowContentView.bottomAnchor)
      ])
    }
  }
}

struct WorkspaceRootView: View {
  @ObservedObject var store: WorkspaceStore
  @ObservedObject private var settings = SettingsStore.shared
  @ObservedObject private var localization = LocalizationController.shared
  @State private var columnVisibility: NavigationSplitViewVisibility = .all

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      WorkspaceSidebar(store: store)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
    } detail: {
      WorkspaceDetail(store: store)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
          if let status = store.status {
            WorkspaceStatusBanner(status: status)
              .padding(QPARKDesign.pagePadding)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }
        .animation(.easeOut(duration: 0.2), value: store.status?.id)
    }
    .toolbar {
      WorkspaceToolbar(store: store)
    }
    .modifier(
      WorkspaceSearchModifier(
        isEnabled: store.selectedSection != .currentSession,
        text: $store.searchText
      )
    )
    .inspector(isPresented: $store.isInspectorVisible) {
      WorkspaceInspector(store: store)
        .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
    }
    .background {
      VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
    }
    .preferredColorScheme(settings.preferredColorScheme)
    .environment(\.locale, localization.locale)
    .environment(\.layoutDirection, localization.layoutDirection)
    .onAppear {
      store.bootstrap()
    }
  }
}

private struct WorkspaceSearchModifier: ViewModifier {
  let isEnabled: Bool
  @Binding var text: String

  @ViewBuilder
  func body(content: Content) -> some View {
    if isEnabled {
      content.searchable(
        text: $text,
        placement: .toolbar,
        prompt: Text(localized("workspace.search_placeholder"))
      )
    } else {
      content
    }
  }
}

private struct WorkspaceToolbar: ToolbarContent {
  @ObservedObject var store: WorkspaceStore

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      Button {
        AppDelegate.shared.triggerCaptureFlow()
      } label: {
        if store.isCapturing {
          Label(localized("status.capturing"), systemImage: "camera.viewfinder")
        } else {
          Label(localized("workspace.capture_cta"), systemImage: "camera.viewfinder")
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(store.isCapturing)
      .help(localized("capture.selected_area"))
      .accessibilityLabel(localized("capture.selected_area"))
      .accessibilityIdentifier("workspace.capture")
    }

    ToolbarItemGroup(placement: .automatic) {
      Button {
        PreferencesWindowController.shared.show()
      } label: {
        Image(systemName: "gearshape")
      }
      .help(localized("common.preferences"))
      .accessibilityLabel(localized("common.preferences"))
      .accessibilityIdentifier("workspace.settings")

      Button {
        store.isInspectorVisible.toggle()
      } label: {
        Image(systemName: "sidebar.right")
      }
      .help(localized("workspace.inspector"))
      .accessibilityLabel(localized("workspace.inspector"))
      .accessibilityValue(store.isInspectorVisible ? localized("status.visible") : localized("status.hidden"))
    }
  }
}

private struct WorkspaceSidebar: View {
  @ObservedObject var store: WorkspaceStore
  @ObservedObject private var queue = ShotQueueStore.shared
  @ObservedObject private var drafts = EditorDraftStore.shared
  @State private var confirmsClear = false

  var body: some View {
    List(selection: sectionBinding) {
      Section {
        ForEach(WorkspaceSection.allCases) { section in
          HStack(spacing: 8) {
            Label(localized(section.titleKey), systemImage: section.iconName)
            Spacer()
            if section == .currentSession, !queue.items.isEmpty {
              Text("\(queue.items.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            } else if section == .missing, !store.missingShots.isEmpty {
              Text("\(store.missingShots.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.orange)
            }
          }
          .tag(section)
          .accessibilityIdentifier("sidebar.\(section.rawValue)")
          .accessibilityValue(section == store.selectedSection ? localized("status.selected") : "")
        }
      } header: {
        HStack(spacing: 9) {
          BrandMark(size: 30)
          Text(localized("app.name"))
            .font(.headline)
        }
        .textCase(nil)
        .padding(.vertical, 6)
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      Button {
        confirmsClear = true
      } label: {
        Label(localized("workspace.clear_session"), systemImage: "trash")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .disabled(queue.items.isEmpty)
      .padding(12)
      .background(.bar)
      .accessibilityHint(localized("workspace.clear_session_message"))
      .accessibilityIdentifier("session.clear")
    }
    .confirmationDialog(
      localized("workspace.clear_session_title"),
      isPresented: $confirmsClear
    ) {
      Button(localized("workspace.clear_session"), role: .destructive) {
        queue.clearAll()
        drafts.clear()
        store.showCurrentSession()
        store.presentStatus(localized("workspace.clear_session"), kind: .success)
      }
      .accessibilityIdentifier("session.clear.confirm")
      Button(localized("common.cancel"), role: .cancel) {}
    } message: {
      Text(clearSessionMessage)
    }
  }

  private var clearSessionMessage: String {
    let count = LocalizationController.shared.format(
      "workspace.clear_session_count",
      queue.temporaryItemCount
    )
    let hasDirtyDrafts = queue.items.contains { drafts.drafts[$0.id]?.isDirty == true }
    return hasDirtyDrafts
      ? count + " " + localized("workspace.unsaved_draft_warning")
      : count
  }

  private var sectionBinding: Binding<WorkspaceSection?> {
    Binding(
      get: { store.selectedSection },
      set: { value in
        if let value {
          select(value)
        }
      }
    )
  }

  private func select(_ section: WorkspaceSection) {
    switch section {
    case .currentSession:
      store.showCurrentSession()
    case .library, .favorites, .recent, .missing:
      store.selectedSection = section
      store.mode = .library
      store.loadLibrary()
    }
  }
}

private struct WorkspaceDetail: View {
  @ObservedObject var store: WorkspaceStore
  @ObservedObject private var queue = ShotQueueStore.shared

  var body: some View {
    Group {
      if store.selectedSection == .currentSession, case .library = store.mode {
        SessionOverviewView(store: store)
      } else {
        switch store.mode {
        case .library:
          LibraryWorkspaceView(store: store)
        case .captureReview(let itemID):
          CaptureReviewView(itemID: itemID, store: store)
        case .editor(let itemID):
          EditorWorkspaceView(itemID: itemID, store: store)
        case .permissionRequired:
          PermissionRequiredView()
        case .error(let message):
          ErrorStateView(message: message)
        }
      }
    }
  }
}

private struct LibraryWorkspaceView: View {
  @ObservedObject var store: WorkspaceStore
  @FocusState private var focusedPath: String?

  var body: some View {
    Group {
      if store.isBusy && store.libraryShots.isEmpty && store.missingShots.isEmpty {
        ProgressView(localized("status.loading"))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if store.selectedSection == .missing {
        missingContent
      } else if store.displayedLibraryShots.isEmpty {
        EmptyLibraryView(
          section: store.selectedSection,
          isSearchEmpty: store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
      } else {
        ScrollView {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)], spacing: 16) {
            ForEach(store.displayedLibraryShots) { shot in
              WorkspaceShotTile(
                shot: shot,
                isSelected: store.selectedLibraryPath == shot.path,
                focus: $focusedPath,
                onSelect: {
                  focusedPath = shot.path
                  store.selectLibraryShot(shot)
                },
                onMoveFocus: { direction in moveFocus(from: shot.path, direction: direction) },
                onOpen: { store.openEditor(forPath: shot.path) },
                onCopy: { store.copyFinalImage(path: shot.path) },
                onShare: { store.share(path: shot.path) },
                onPin: { store.pin(path: shot.path) },
                onFavorite: { store.toggleFavorite(path: shot.path) },
                onDelete: { store.deleteLibraryShot(path: shot.path) }
              )
            }
          }
          .padding(QPARKDesign.pagePadding)
        }
      }
    }
    .onChange(of: store.searchText) {
      focusedPath = nil
    }
  }

  @ViewBuilder
  private var missingContent: some View {
    if store.displayedMissingShots.isEmpty {
      ContentUnavailableView(
        localized("workspace.no_missing"),
        systemImage: "checkmark.circle",
        description: Text(
          store.searchText.isEmpty
            ? localized("workspace.missing_hint")
            : localized("workspace.no_matches")
        )
      )
    } else {
      ScrollView {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 16)],
          spacing: 16
        ) {
          ForEach(store.displayedMissingShots) { shot in
            MissingShotTile(
              shot: shot,
              isSelected: store.selectedLibraryPath == shot.path,
              onSelect: { store.selectMissingShot(shot) },
              onLocate: { locate(shot) },
              onForget: { store.forgetMissing(path: shot.path) }
            )
          }
        }
        .padding(QPARKDesign.pagePadding)
      }
    }
  }

  private func locate(_ shot: GalleryIndexEntry) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.image]
    panel.prompt = localized("common.locate")
    if panel.runModal() == .OK, let url = panel.url {
      let bookmark = try? url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      store.relinkMissing(from: shot.path, to: url, bookmarkData: bookmark)
    }
  }

  private func moveFocus(from path: String, direction: MoveCommandDirection) {
    let shots = store.displayedLibraryShots
    guard let index = shots.firstIndex(where: { $0.path == path }) else { return }
    let delta = direction == .left || direction == .up ? -1 : 1
    let nextIndex = min(max(index + delta, 0), shots.count - 1)
    let next = shots[nextIndex]
    focusedPath = next.path
    store.selectLibraryShot(next)
  }
}

private struct WorkspaceShotTile: View {
  let shot: LibraryShot
  let isSelected: Bool
  let focus: FocusState<String?>.Binding
  let onSelect: () -> Void
  let onMoveFocus: (MoveCommandDirection) -> Void
  let onOpen: () -> Void
  let onCopy: () -> Void
  let onShare: () -> Void
  let onPin: () -> Void
  let onFavorite: () -> Void
  let onDelete: () -> Void

  @State private var thumbnail: NSImage?
  @State private var isHovered = false

  private var isFocused: Bool { focus.wrappedValue == shot.path }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Button(action: activate) {
        VStack(alignment: .leading, spacing: 8) {
          ImagePreview(image: thumbnail, cornerRadius: QPARKDesign.previewRadius)
            .aspectRatio(1.45, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
              if shot.entry.favorite {
                Image(systemName: "star.fill")
                  .foregroundStyle(.yellow)
                  .padding(8)
                  .accessibilityHidden(true)
              }
            }

          Text(shot.url.lastPathComponent)
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .truncationMode(.middle)

          Text(shot.createdAt, format: .dateTime.day().month().year().hour().minute())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
          RoundedRectangle(cornerRadius: QPARKDesign.cardRadius, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(isHovered ? 0.06 : 0.035))
        }
        .overlay {
          RoundedRectangle(cornerRadius: QPARKDesign.cardRadius, style: .continuous)
            .stroke(
              isFocused ? QPARKDesign.brandCyan : (isSelected ? Color.accentColor : Color.primary.opacity(0.10)),
              lineWidth: isFocused || isSelected ? 2 : 1
            )
        }
      }
      .buttonStyle(.plain)
      .focused(focus, equals: shot.path)
      .simultaneousGesture(TapGesture(count: 2).onEnded(onOpen))
      .onKeyPress(.return) {
        onOpen()
        return .handled
      }
      .onMoveCommand(perform: onMoveFocus)
      .accessibilityLabel(shot.url.lastPathComponent)
      .accessibilityValue(isSelected ? localized("status.selected") : "")
      .accessibilityHint(localized("common.edit"))
      .accessibilityIdentifier("shot.\(shot.url.lastPathComponent)")

      if isHovered || isFocused {
        HStack(spacing: 4) {
          tileAction(localized("common.edit"), icon: "pencil", action: onOpen)
          tileAction(localized("common.copy"), icon: "doc.on.doc", action: onCopy)
          tileAction(localized("common.share"), icon: "square.and.arrow.up", action: onShare)
          Menu {
            Button(localized("common.pin"), action: onPin)
            Button(
              shot.entry.favorite ? localized("common.remove_favorite") : localized("common.favorite"),
              action: onFavorite
            )
            Button(localized("common.show_in_finder")) {
              NSWorkspace.shared.activateFileViewerSelecting([shot.url])
            }
            Divider()
            Button(localized("common.move_to_trash"), role: .destructive, action: onDelete)
          } label: {
            Image(systemName: "ellipsis.circle.fill")
          }
          .menuStyle(.borderlessButton)
          .help(localized("common.more"))
          .accessibilityLabel(localized("common.more"))
        }
        .controlSize(.small)
        .padding(14)
        .transition(.opacity)
      }

    }
    .onHover { isHovered = $0 }
    .onAppear(perform: loadThumbnail)
    .draggable(shot.url)
    .contextMenu {
      Button(localized("common.edit"), action: onOpen)
      Button(localized("common.copy"), action: onCopy)
      Button(localized("common.share"), action: onShare)
      Button(localized("common.pin"), action: onPin)
      Button(shot.entry.favorite ? localized("common.remove_favorite") : localized("common.favorite"), action: onFavorite)
      Button(localized("common.show_in_finder")) {
        NSWorkspace.shared.activateFileViewerSelecting([shot.url])
      }
      Divider()
      Button(localized("common.move_to_trash"), role: .destructive, action: onDelete)
    }
  }

  private func tileAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .frame(width: 20, height: 20)
    }
    .buttonStyle(.bordered)
    .help(title)
    .accessibilityLabel(title)
  }

  private func activate() {
    let eventType = NSApp.currentEvent?.type
    let isMouseActivation = eventType == .leftMouseDown || eventType == .leftMouseUp
    if isSelected && !isMouseActivation {
      onOpen()
    } else {
      onSelect()
    }
  }

  private func loadThumbnail() {
    guard thumbnail == nil else { return }
    let path = shot.path
    DispatchQueue.global(qos: .utility).async {
      let image = makeThumbnailImage(path: path, maxPixelSize: 480)
      DispatchQueue.main.async {
        thumbnail = image
      }
    }
  }
}

private struct MissingShotTile: View {
  let shot: GalleryIndexEntry
  let isSelected: Bool
  let onSelect: () -> Void
  let onLocate: () -> Void
  let onForget: () -> Void
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "photo.badge.exclamationmark")
            .font(.title2)
            .foregroundStyle(.orange)
            .frame(width: 34, height: 34)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
          VStack(alignment: .leading, spacing: 4) {
            Text(shot.fileName)
              .font(.headline)
              .lineLimit(2)
            Text(shot.path)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
              .truncationMode(.middle)
          }
        }

        HStack {
          Button(localized("common.locate"), action: onLocate)
            .buttonStyle(.borderedProminent)
          Button(localized("common.forget"), role: .destructive, action: onForget)
            .buttonStyle(.bordered)
          Spacer()
          if let missingSince = shot.missingSince {
            Text(missingSince, format: .dateTime.day().month().year())
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .qparkSurface(emphasized: isSelected || isFocused)
    .contentShape(Rectangle())
    .onTapGesture(perform: onSelect)
    .focusable()
    .focused($isFocused)
    .onKeyPress(.return) {
      onSelect()
      return .handled
    }
    .accessibilityLabel(shot.fileName)
    .accessibilityHint(localized("workspace.missing_hint"))
  }
}

private struct EmptyLibraryView: View {
  let section: WorkspaceSection
  let isSearchEmpty: Bool

  var body: some View {
    ContentUnavailableView {
      Label(title, systemImage: systemImage)
    } description: {
      if !isSearchEmpty {
        Text(localized("workspace.no_matches"))
      }
    } actions: {
      Button {
        AppDelegate.shared.triggerCaptureFlow()
      } label: {
        Label(localized("workspace.capture_cta"), systemImage: "camera.viewfinder")
      }
      .buttonStyle(.borderedProminent)
    }
  }

  private var title: String {
    if !isSearchEmpty { return localized("workspace.no_matches") }
    return section == .recent ? localized("workspace.no_recent") : localized("workspace.no_shots")
  }

  private var systemImage: String {
    section == .recent ? "clock" : "photo.on.rectangle.angled"
  }
}

private struct SessionOverviewView: View {
  @ObservedObject var store: WorkspaceStore
  @ObservedObject private var queue = ShotQueueStore.shared
  @ObservedObject private var drafts = EditorDraftStore.shared

  var body: some View {
    if queue.items.isEmpty {
      ContentUnavailableView {
        Label(localized("workspace.empty_session"), systemImage: "tray")
      } actions: {
        Button {
          AppDelegate.shared.triggerCaptureFlow()
        } label: {
          Label(localized("workspace.capture_cta"), systemImage: "camera.viewfinder")
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isCapturing)
      }
    } else {
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 14)], spacing: 14) {
          ForEach(queue.items) { item in
            SessionItemTile(
              item: item,
              onOpen: { store.showCaptureReview(itemID: item.id) },
              onEdit: { store.openEditor(itemID: item.id) },
              onRemove: {
                _ = queue.remove(item.id)
                EditorDraftStore.shared.remove(item.id)
                store.showCurrentSession()
              },
              isDirty: drafts.draft(for: item.id).isDirty
            )
          }
        }
        .padding(18)
      }
    }
  }
}

private struct SessionItemTile: View {
  let item: ShotQueueItem
  let onOpen: () -> Void
  let onEdit: () -> Void
  let onRemove: () -> Void
  let isDirty: Bool

  @State private var thumbnail: NSImage?
  @State private var confirmsRemove = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ImagePreview(image: thumbnail, cornerRadius: 8)
        .aspectRatio(1.55, contentMode: .fit)
      Text(item.capturedAt, style: .time)
        .font(.caption.weight(.medium))
      HStack(spacing: 8) {
        Button(localized("common.open"), action: onOpen)
        Button(localized("common.edit"), action: onEdit)
        Spacer()
        Button(role: .destructive) {
          if isDirty {
            confirmsRemove = true
          } else {
            onRemove()
          }
        } label: {
          Image(systemName: "trash")
        }
        .accessibilityLabel(localized("common.delete"))
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .padding(10)
    .background(Color.primary.opacity(0.05))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .onAppear(perform: loadThumbnail)
    .confirmationDialog(
      localized("workspace.clear_session_title"),
      isPresented: $confirmsRemove
    ) {
      Button(localized("common.delete"), role: .destructive, action: onRemove)
      Button(localized("common.cancel"), role: .cancel) {}
    } message: {
      Text(localized("workspace.unsaved_draft_warning"))
    }
  }

  private func loadThumbnail() {
    guard thumbnail == nil else { return }
    DispatchQueue.global(qos: .utility).async {
      let image = makeThumbnailImage(path: item.path, maxPixelSize: 560)
      DispatchQueue.main.async {
        thumbnail = image
      }
    }
  }
}

private struct CaptureReviewView: View {
  let itemID: UUID
  @ObservedObject var store: WorkspaceStore
  @ObservedObject private var queue = ShotQueueStore.shared
  @ObservedObject private var settings = SettingsStore.shared
  @State private var image: NSImage?
  @State private var previewImage: NSImage?
  @State private var isBusy = false
  @State private var previewRequestID = UUID()

  private var item: ShotQueueItem? {
    queue.item(for: itemID)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Label(localized("review.captured"), systemImage: "checkmark.circle.fill")
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.green)
        Spacer()
        Button {
          store.showSessionOverview()
        } label: {
          Image(systemName: "xmark")
        }
        .help(localized("common.close"))
      }
      .padding(14)

      Divider()

      VStack(spacing: 16) {
        ImagePreview(image: previewImage ?? image, cornerRadius: 10)
          .frame(maxWidth: 760, maxHeight: 430)

        HStack(spacing: 10) {
          Button {
            copy()
          } label: {
            Label(localized("common.copy"), systemImage: "doc.on.doc")
          }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("review.copy")

          Button {
            if let item {
              store.openEditor(itemID: item.id)
            }
          } label: {
            Label(localized("settings.open_editor"), systemImage: "pencil.and.outline")
          }

          Button {
            save()
          } label: {
            Label(localized("common.save"), systemImage: "square.and.arrow.down")
          }

          Button {
            share()
          } label: {
            Label(localized("common.share"), systemImage: "square.and.arrow.up")
          }

          Button {
            pin()
          } label: {
            Label(localized("common.pin"), systemImage: "pin")
          }
        }
        .buttonStyle(.bordered)
        .disabled(isBusy || item == nil)
      }
      .padding(20)
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      if shouldShowSessionStrip(isEnabled: settings.queuePanelEnabled, itemCount: queue.items.count) {
        Divider()
        SessionStrip(activeID: itemID, store: store, action: .review)
          .frame(height: 88)
      }
    }
    .onAppear(perform: loadImage)
    .onReceive(settings.objectWillChange) { _ in
      DispatchQueue.main.async {
        renderPreview()
      }
    }
  }

  private func loadImage() {
    guard let path = item?.path else { return }
    DispatchQueue.global(qos: .userInitiated).async {
      let loaded = loadImageForRendering(path: path)
      DispatchQueue.main.async {
        image = loaded
        renderPreview()
      }
    }
  }

  private func renderPreview() {
    guard let image else {
      previewImage = nil
      return
    }
    let requestID = UUID()
    previewRequestID = requestID
    let preset = ExportPreset.preset(for: SettingsStore.shared.exportPresetID)
    let watermark = WatermarkRenderSettings.current()
    DispatchQueue.global(qos: .userInitiated).async {
      let rendered = ExportService.shared.render(
        ExportContext(
          image: image,
          annotations: [],
          cropRect: nil,
          preset: preset,
          watermark: watermark
        )
      )
      DispatchQueue.main.async {
        guard previewRequestID == requestID else { return }
        previewImage = rendered
      }
    }
  }

  private func save() {
    exportFinal(isTemporary: false) { savedPath in
      if savedPath != nil {
        store.presentStatus(localized("review.saved"), kind: .success)
        store.loadLibrary()
      } else {
        store.presentStatus(localized("review.save_failed"), kind: .error)
      }
    }
  }

  private func copy() {
    guard let image else { return }
    exportRenderedImage(from: image) { rendered in
      isBusy = false
      guard let rendered else {
        store.presentStatus(localized("status.copy_failed"), kind: .error)
        return
      }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.writeObjects([rendered])
      store.presentStatus(localized("review.copied"), kind: .success)
    }
  }

  private func share() {
    exportFinal(isTemporary: true) { savedPath in
      if let savedPath {
        store.share(path: savedPath)
      }
    }
  }

  private func pin() {
    exportFinal(isTemporary: true) { savedPath in
      if let savedPath {
        store.pin(path: savedPath)
      }
    }
  }

  private func exportFinal(isTemporary: Bool, completion: @escaping (String?) -> Void) {
    guard let image else {
      completion(nil)
      return
    }
    isBusy = true
    let preset = ExportPreset.preset(for: SettingsStore.shared.exportPresetID)
    let template = SettingsStore.shared.filenameTemplate
    let watermark = WatermarkRenderSettings.current()
    DispatchQueue.global(qos: .userInitiated).async {
      let savedPath = ExportService.shared.save(
        context: ExportContext(
          image: image,
          annotations: [],
          cropRect: nil,
          preset: preset,
          watermark: watermark
        ),
        isTemporary: isTemporary,
        filenameTemplate: template
      )
      DispatchQueue.main.async {
        isBusy = false
        completion(savedPath)
      }
    }
  }

  private func exportRenderedImage(from image: NSImage, completion: @escaping (NSImage?) -> Void) {
    isBusy = true
    let preset = ExportPreset.preset(for: SettingsStore.shared.exportPresetID)
    let watermark = WatermarkRenderSettings.current()
    DispatchQueue.global(qos: .userInitiated).async {
      let rendered = ExportService.shared.render(
        ExportContext(
          image: image,
          annotations: [],
          cropRect: nil,
          preset: preset,
          watermark: watermark
        )
      )
      DispatchQueue.main.async {
        completion(rendered)
      }
    }
  }
}

private struct EditorWorkspaceView: View {
  let itemID: UUID
  @ObservedObject var store: WorkspaceStore
  @ObservedObject private var queue = ShotQueueStore.shared
  @ObservedObject private var drafts = EditorDraftStore.shared
  @ObservedObject private var settings = SettingsStore.shared

  @State private var image: NSImage?
  @State private var annotations: [Annotation] = []
  @State private var cropRect: CGRect?
  @State private var currentTool: ToolType = .arrow
  @State private var currentColor: Color = .red
  @State private var currentStrokeWidth: CGFloat = 4
  @State private var textInput: String = ""
  @State private var isExporting = false

  private var item: ShotQueueItem? {
    queue.item(for: itemID)
  }

  var body: some View {
    VStack(spacing: 0) {
      editorToolbar
      Divider()
      HStack(spacing: 0) {
        ZStack {
          Color.black.opacity(0.84)
          if let image {
            DrawingCanvas(
              image: image,
              annotations: $annotations,
              currentTool: $currentTool,
              currentColor: $currentColor,
              currentStrokeWidth: $currentStrokeWidth,
              textInput: $textInput,
              cropRect: $cropRect,
              onAction: recordDraft
            )
            .padding(18)
          } else {
            ProgressView()
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        EditorControls(
          currentTool: $currentTool,
          currentColor: $currentColor,
          currentStrokeWidth: $currentStrokeWidth,
          textInput: $textInput,
          hasCrop: cropRect != nil,
          onClearCrop: {
            cropRect = nil
            recordDraft()
          }
        )
        .frame(width: 250)
      }
      if shouldShowSessionStrip(isEnabled: settings.queuePanelEnabled, itemCount: queue.items.count) {
        Divider()
        SessionStrip(activeID: itemID, store: store)
          .frame(height: 96)
      }
    }
    .onAppear(perform: loadState)
    .onChange(of: itemID) {
      loadState()
    }
  }

  private var editorToolbar: some View {
    HStack(spacing: 8) {
      Button {
        store.showSessionOverview()
      } label: {
        Label(localized("common.back"), systemImage: "chevron.left")
      }
      .buttonStyle(.bordered)

      Divider()
        .frame(height: 20)

      Button(action: undo) {
        Image(systemName: "arrow.uturn.backward")
      }
      .keyboardShortcut("z", modifiers: .command)
      .accessibilityLabel(localized("editor.undo"))
      .accessibilityIdentifier("editor.undo")
      .help(localized("editor.undo"))
      .disabled(drafts.draft(for: itemID).undoStack.count <= 1)

      Button(action: redo) {
        Image(systemName: "arrow.uturn.forward")
      }
      .keyboardShortcut("z", modifiers: [.command, .shift])
      .accessibilityLabel(localized("editor.redo"))
      .accessibilityIdentifier("editor.redo")
      .help(localized("editor.redo"))
      .disabled(drafts.draft(for: itemID).redoStack.isEmpty)

      Spacer()

      Button(action: copyFinal) {
        Label(localized("common.copy"), systemImage: "doc.on.doc")
      }
      Button(action: shareFinal) {
        Label(localized("common.share"), systemImage: "square.and.arrow.up")
      }
      Button(action: pinFinal) {
        Label(localized("common.pin"), systemImage: "pin")
      }
      Button(action: saveFinal) {
        Label(localized("common.save"), systemImage: "square.and.arrow.down")
      }
      .buttonStyle(.borderedProminent)
      .keyboardShortcut("s", modifiers: .command)
      .accessibilityIdentifier("editor.save")
    }
    .buttonStyle(.bordered)
    .disabled(isExporting)
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
  }

  private func loadState() {
    guard let item else { return }
    let draft = drafts.draft(for: itemID)
    annotations = draft.annotations
    cropRect = draft.cropRect
    DispatchQueue.global(qos: .userInitiated).async {
      let loaded = loadImageForRendering(path: item.path)
      DispatchQueue.main.async {
        image = loaded
      }
    }
  }

  private func recordDraft() {
    drafts.recordAnnotations(annotations, cropRect: cropRect, for: itemID)
  }

  private func undo() {
    drafts.update(itemID) { draft in
      guard draft.undoStack.count > 1 else { return }
      let current = draft.undoStack.removeLast()
      draft.redoStack.append(current)
      let previous = draft.undoStack.last ?? []
      draft.annotations = previous
      draft.isDirty = true
      annotations = previous
    }
  }

  private func redo() {
    drafts.update(itemID) { draft in
      guard let next = draft.redoStack.popLast() else { return }
      draft.undoStack.append(next)
      draft.annotations = next
      draft.isDirty = true
      annotations = next
    }
  }

  private func saveFinal() {
    exportFinal(isTemporary: false) { savedPath in
      if savedPath != nil {
        drafts.markSaved(itemID)
        store.presentStatus(localized("editor.saved"), kind: .success)
        store.loadLibrary()
      } else {
        store.presentStatus(localized("review.save_failed"), kind: .error)
      }
    }
  }

  private func copyFinal() {
    guard let image = image else { return }
    isExporting = true
    let annotations = annotations
    let cropRect = cropRect
    DispatchQueue.global(qos: .userInitiated).async {
      let rendered = ExportService.shared.render(
        ExportContext(
          image: image,
          annotations: annotations,
          cropRect: cropRect,
          preset: ExportPreset.preset(for: SettingsStore.shared.exportPresetID),
          watermark: WatermarkRenderSettings.current()
        )
      )
      DispatchQueue.main.async {
        isExporting = false
        guard let rendered else {
          store.presentStatus(localized("status.copy_failed"), kind: .error)
          return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([rendered])
        store.presentStatus(localized("review.copied"), kind: .success)
      }
    }
  }

  private func shareFinal() {
    exportFinal(isTemporary: true) { savedPath in
      if let savedPath {
        store.share(path: savedPath)
      }
    }
  }

  private func pinFinal() {
    exportFinal(isTemporary: true) { savedPath in
      if let savedPath {
        store.pin(path: savedPath)
      }
    }
  }

  private func exportFinal(isTemporary: Bool, completion: @escaping (String?) -> Void) {
    guard let image else {
      completion(nil)
      return
    }
    isExporting = true
    let annotations = annotations
    let cropRect = cropRect
    let preset = ExportPreset.preset(for: SettingsStore.shared.exportPresetID)
    let template = SettingsStore.shared.filenameTemplate
    DispatchQueue.global(qos: .userInitiated).async {
      let savedPath = ExportService.shared.save(
        context: ExportContext(
          image: image,
          annotations: annotations,
          cropRect: cropRect,
          preset: preset,
          watermark: WatermarkRenderSettings.current()
        ),
        isTemporary: isTemporary,
        filenameTemplate: template
      )
      DispatchQueue.main.async {
        isExporting = false
        completion(savedPath)
      }
    }
  }
}

private struct EditorControls: View {
  @Binding var currentTool: ToolType
  @Binding var currentColor: Color
  @Binding var currentStrokeWidth: CGFloat
  @Binding var textInput: String
  let hasCrop: Bool
  let onClearCrop: () -> Void

  private let tools: [(ToolType, String, String)] = [
    (.arrow, "editor.tool_arrow", "arrow.up.right"),
    (.rectangle, "editor.tool_rectangle", "rectangle"),
    (.freehand, "editor.tool_freehand", "scribble"),
    (.text, "editor.tool_text", "textformat"),
    (.callout, "editor.tool_callout", "number.circle"),
    (.redact, "editor.tool_redact", "eye.slash"),
    (.blur, "editor.tool_blur", "drop"),
    (.select, "editor.tool_crop", "crop")
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(localized("editor.tools"))
        .font(.body.weight(.semibold))

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 54), spacing: 8)], spacing: 8) {
        ForEach(tools, id: \.1) { tool, key, icon in
          Button {
            currentTool = tool
          } label: {
            Image(systemName: icon)
              .frame(width: 34, height: 28)
          }
          .buttonStyle(.bordered)
          .help(localized(key))
          .tint(currentTool == tool ? QPARKDesign.brandCyan : nil)
          .accessibilityLabel(localized(key))
          .accessibilityValue(currentTool == tool ? localized("status.selected") : "")
        }
      }

      ColorPicker(localized("editor.color"), selection: $currentColor)

      VStack(alignment: .leading) {
        Text(localized("editor.stroke"))
          .font(.caption)
          .foregroundColor(.secondary)
        Slider(value: Binding(
          get: { Double(currentStrokeWidth) },
          set: { currentStrokeWidth = CGFloat($0) }
        ), in: 1...18, step: 1)
        .accessibilityLabel(localized("editor.stroke"))
        .accessibilityValue("\(Int(currentStrokeWidth)) pt")
      }

      TextField(localized("editor.text_placeholder"), text: $textInput)
        .textFieldStyle(.roundedBorder)

      Button {
        onClearCrop()
      } label: {
        Label(localized("editor.clear_crop"), systemImage: "crop")
      }
      .disabled(!hasCrop)

      Spacer()
    }
    .padding(14)
    .background(Color.primary.opacity(0.04))
  }
}

private struct SessionStrip: View {
  enum Action {
    case edit
    case review
  }

  let activeID: UUID
  @ObservedObject var store: WorkspaceStore
  var action: Action = .edit
  @ObservedObject private var queue = ShotQueueStore.shared

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(queue.items) { item in
          ShotQueueThumbnail(item: item, isActive: item.id == activeID) {
            switch action {
            case .edit:
              store.openEditor(itemID: item.id)
            case .review:
              store.showCaptureReview(itemID: item.id)
            }
          }
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
    }
  }
}

private struct ShotQueueThumbnail: View {
  let item: ShotQueueItem
  let isActive: Bool
  let onSelect: () -> Void

  @State private var thumbnail: NSImage?

  var body: some View {
    Button(action: onSelect) {
      ImagePreview(image: thumbnail, cornerRadius: 6)
        .frame(width: 112, height: 68)
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.22), lineWidth: isActive ? 2 : 1)
        )
    }
    .buttonStyle(.plain)
    .onAppear(perform: loadThumbnail)
  }

  private func loadThumbnail() {
    guard thumbnail == nil else { return }
    DispatchQueue.global(qos: .utility).async {
      let image = makeThumbnailImage(path: item.path, maxPixelSize: 260)
      DispatchQueue.main.async {
        thumbnail = image
      }
    }
  }
}

private struct WorkspaceInspector: View {
  @ObservedObject var store: WorkspaceStore
  @ObservedObject private var queue = ShotQueueStore.shared
  @ObservedObject private var galleryIndex = GalleryIndexStore.shared
  @State private var tagsText = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(localized("workspace.inspector"))
        .font(.body.weight(.semibold))

      if store.selectedSection == .currentSession {
        sessionInspector
      } else if store.selectedSection == .missing, let shot = store.selectedMissingShot {
        missingInspector(shot)
      } else if let shot = store.selectedShot {
        libraryInspector(shot)
      } else {
        Text(localized("workspace.no_selection"))
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Spacer()
    }
    .padding(14)
    .onAppear(perform: refreshTagsText)
    .onChange(of: store.selectedLibraryPath) {
      refreshTagsText()
    }
  }

  private var sessionInspector: some View {
    VStack(alignment: .leading, spacing: 9) {
      Label("\(queue.items.count)", systemImage: "tray.full")
        .font(.caption)
      if let activeID = queue.activeID, let item = queue.item(for: activeID) {
        Text(item.path)
          .font(.caption2)
          .foregroundColor(.secondary)
          .lineLimit(4)
          .truncationMode(.middle)
      }
    }
  }

  private func libraryInspector(_ shot: LibraryShot) -> some View {
    let entry = galleryIndex.entry(for: shot.path)
    return VStack(alignment: .leading, spacing: 11) {
      Text(shot.url.lastPathComponent)
        .font(.caption.weight(.medium))
        .lineLimit(2)
      Text(shot.path)
        .font(.caption2)
        .foregroundColor(.secondary)
        .lineLimit(4)
        .truncationMode(.middle)
      HStack {
        Button(localized("common.edit")) {
          store.openEditor(forPath: shot.path)
        }
        Button(localized("common.show_in_finder")) {
          NSWorkspace.shared.activateFileViewerSelecting([shot.url])
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      Toggle(isOn: Binding(
        get: { entry.favorite },
        set: { _ in store.toggleFavorite(path: shot.path) }
      )) {
        Text(localized("common.favorite"))
      }
      .toggleStyle(.checkbox)

      Divider()

      VStack(alignment: .leading, spacing: 6) {
        Text(localized("inspector.tags"))
          .font(.body.weight(.medium))
        HStack {
          TextField(localized("inspector.tags_hint"), text: $tagsText)
            .textFieldStyle(.roundedBorder)
            .onSubmit { store.updateTags(path: shot.path, text: tagsText) }
          Button(localized("common.save")) {
            store.updateTags(path: shot.path, text: tagsText)
          }
        }
      }

      Divider()

      VStack(alignment: .leading, spacing: 6) {
        Text(localized("inspector.ocr"))
          .font(.caption.weight(.semibold))
        ocrStatus(for: shot.path, entry: entry)
      }
    }
  }

  private func missingInspector(_ shot: GalleryIndexEntry) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Label(shot.fileName, systemImage: "photo.badge.exclamationmark")
        .font(.headline)
        .foregroundStyle(.orange)
      Text(shot.path)
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
      if !shot.tags.isEmpty {
        Text(shot.tags.joined(separator: ", "))
          .font(.caption)
      }
    }
  }

  private func refreshTagsText() {
    guard let path = store.selectedLibraryPath,
          store.selectedSection != .missing else {
      tagsText = ""
      return
    }
    tagsText = galleryIndex.entry(for: path).tags.joined(separator: ", ")
  }

  @ViewBuilder
  private func ocrStatus(for path: String, entry: GalleryIndexEntry) -> some View {
    if !SettingsStore.shared.galleryOCREnabled {
      Text(localized("status.ocr_disabled"))
        .font(.caption2)
        .foregroundColor(.secondary)
    } else if store.isOCRRunning(for: path) || entry.ocrIndexedAt == nil {
      Label(localized("status.indexing"), systemImage: "text.viewfinder")
        .font(.caption2)
        .foregroundColor(.secondary)
    } else if entry.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      Text(localized("status.no_text"))
        .font(.caption2)
        .foregroundColor(.secondary)
    } else {
      Text(entry.ocrText)
        .font(.caption2)
        .foregroundColor(.secondary)
        .lineLimit(8)
        .textSelection(.enabled)
    }
  }
}

private struct PermissionRequiredView: View {
  var body: some View {
    ContentUnavailableView {
      Label(localized("permission.title"), systemImage: "lock.shield")
    } description: {
      Text(localized("permission.message"))
    } actions: {
      Button {
        AppDelegate.shared.openScreenRecordingSettings()
      } label: {
        Label(localized("permission.open_settings"), systemImage: "gearshape")
      }
      .buttonStyle(.borderedProminent)
      .accessibilityIdentifier("permission.openSettings")
    }
  }
}

private struct ErrorStateView: View {
  let message: String

  var body: some View {
    ContentUnavailableView {
      Label(localized("status.capture_failed"), systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      Button {
        AppDelegate.shared.triggerCaptureFlow()
      } label: {
        Label(localized("common.retry"), systemImage: "arrow.clockwise")
      }
      .buttonStyle(.borderedProminent)
      .accessibilityIdentifier("error.retry")
    }
  }
}

private struct ImagePreview: View {
  let image: NSImage?
  let cornerRadius: CGFloat

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(Color.black.opacity(0.78))
      if let image {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .padding(8)
      } else {
        ProgressView()
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

#if DEBUG
private struct WorkspaceSurfacePreview<Content: View>: View {
  let language: AppLanguage
  let content: Content
  @ObservedObject private var localization = LocalizationController.shared

  init(language: AppLanguage, @ViewBuilder content: () -> Content) {
    self.language = language
    self.content = content()
  }

  var body: some View {
    content
      .environment(\.locale, language.locale)
      .environment(\.layoutDirection, language.layoutDirection)
      .onAppear {
        SettingsStore.shared.appLanguageCode = language.rawValue
        localization.refreshFromSettings()
      }
  }
}

private func previewQueueItemID() -> UUID {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent("qpark-shot-preview.png")
  if !FileManager.default.fileExists(atPath: url.path),
     let image = NSImage(named: NSImage.applicationIconName),
     let data = ExportService.shared.pngData(from: image) {
    try? data.write(to: url, options: .atomic)
  }
  return ShotQueueStore.shared.enqueue(path: url.path).id
}

private struct WorkspaceSurfacePreviews: PreviewProvider {
  static var previews: some View {
    Group {
      WorkspaceSurfacePreview(language: .russian) {
        WorkspaceRootView(store: .shared).frame(width: 920, height: 620)
      }
      .preferredColorScheme(.light)
      .previewDisplayName("Library · RU · Light · 920×620")

      WorkspaceSurfacePreview(language: .arabic) {
        WorkspaceRootView(store: .shared).frame(width: 1280, height: 800)
      }
      .preferredColorScheme(.dark)
      .previewDisplayName("Library · Arabic RTL · Dark · 1280×800")

      WorkspaceSurfacePreview(language: .german) {
        CaptureReviewView(itemID: previewQueueItemID(), store: .shared).frame(width: 920, height: 620)
      }
      .preferredColorScheme(.light)
      .previewDisplayName("Review · DE · Light")

      WorkspaceSurfacePreview(language: .russian) {
        CaptureReviewView(itemID: previewQueueItemID(), store: .shared).frame(width: 1280, height: 800)
      }
      .preferredColorScheme(.dark)
      .previewDisplayName("Review · RU · Dark")

      EditorWorkspaceView(itemID: previewQueueItemID(), store: .shared)
        .frame(width: 1280, height: 800)
        .preferredColorScheme(.light)
        .previewDisplayName("Editor · Light · 1280×800")

      WorkspaceSurfacePreview(language: .arabic) {
        EditorWorkspaceView(itemID: previewQueueItemID(), store: .shared).frame(width: 920, height: 620)
      }
      .preferredColorScheme(.dark)
      .previewDisplayName("Editor · Arabic RTL · Dark · 920×620")

      WorkspaceSurfacePreview(language: .german) {
        PermissionRequiredView().frame(width: 920, height: 620)
      }
      .preferredColorScheme(.light)
      .previewDisplayName("Permission · DE · Light")

      WorkspaceSurfacePreview(language: .russian) {
        ErrorStateView(message: localized("status.capture_failed")).frame(width: 1280, height: 800)
      }
      .preferredColorScheme(.dark)
      .previewDisplayName("Error · RU · Dark")
    }
  }
}
#endif
