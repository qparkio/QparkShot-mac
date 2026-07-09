import AppKit
import SwiftUI

final class PinnedShotWindowController: NSObject, NSWindowDelegate {
  static let shared = PinnedShotWindowController()

  private var windows: [NSWindow] = []

  private override init() {}

  func pinImage(at path: String) {
    guard let image = loadImageForRendering(path: path) else { return }

    let windowBox = WeakWindowBox()
    let content = PinnedShotView(
      image: image,
      path: path,
      onClose: { [weak self] in
        self?.close(windowBox.window)
      }
    )

    let hostingController = NSHostingController(rootView: content)
    let imageSize = image.size
    let maxWidth: CGFloat = 520
    let maxHeight: CGFloat = 420
    let scale = min(maxWidth / max(imageSize.width, 1), maxHeight / max(imageSize.height, 1), 1)
    let contentSize = CGSize(
      width: max(240, imageSize.width * scale),
      height: max(180, imageSize.height * scale) + 36
    )

    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: contentSize),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = localized("review.pinned")
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentViewController = hostingController
    window.center()
    window.makeKeyAndOrderFront(nil)
    windowBox.window = window

    windows.append(window)
  }

  private func close(_ window: NSWindow?) {
    guard let window else { return }
    window.close()
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    windows.removeAll { $0 === window }
  }
}

private final class WeakWindowBox {
  weak var window: NSWindow?
}

private struct PinnedShotView: View {
  let image: NSImage
  let path: String
  let onClose: () -> Void

  @Environment(\.controlActiveState) private var controlActiveState

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Button {
          copyImage()
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .help(localized("common.copy"))

        Button {
          shareImage()
        } label: {
          Image(systemName: "square.and.arrow.up")
        }
        .help(localized("common.share"))

        Button {
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } label: {
          Image(systemName: "finder")
        }
        .help(localized("common.show_in_finder"))

        Spacer()

        Button {
          onClose()
        } label: {
          Image(systemName: "xmark")
        }
        .help(localized("common.close"))
      }
      .buttonStyle(.borderless)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))

      Divider()

      Image(nsImage: image)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(controlActiveState == .inactive ? 0.72 : 0.82))
    }
  }

  private func copyImage() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects([image])
  }

  private func shareImage() {
    guard let window = NSApp.keyWindow, let contentView = window.contentView else { return }
    let picker = NSSharingServicePicker(items: [URL(fileURLWithPath: path)])
    let rect = NSRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
    picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
  }
}
