import AppKit
import Foundation

struct CaptureRegion: Codable, Equatable {
  var x: Double
  var y: Double
  var width: Double
  var height: Double

  init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  init(rect: CGRect) {
    self.init(
      x: Double(rect.origin.x.rounded()),
      y: Double(rect.origin.y.rounded()),
      width: Double(rect.size.width.rounded()),
      height: Double(rect.size.height.rounded())
    )
  }

  var cgRect: CGRect {
    CGRect(x: x, y: y, width: width, height: height)
  }

  var isUsable: Bool {
    width >= 4 && height >= 4
  }

  var screencaptureArgumentValue: String {
    "\(Int(x)),\(Int(y)),\(Int(width)),\(Int(height))"
  }
}

enum CaptureMode: String, Codable, CaseIterable {
  case selection
  case fullScreen
  case window
  case repeatLastArea
}

struct CaptureRequest: Equatable {
  var mode: CaptureMode
  var delaySeconds: Int
  var outputURL: URL
  var repeatRegion: CaptureRegion?

  init(
    mode: CaptureMode,
    delaySeconds: Int = 0,
    outputURL: URL,
    repeatRegion: CaptureRegion? = nil
  ) {
    self.mode = mode
    self.delaySeconds = max(0, delaySeconds)
    self.outputURL = outputURL
    self.repeatRegion = repeatRegion
  }
}

enum CaptureServiceError: Error, Equatable {
  case missingRepeatRegion
  case failedToRun(String)
  case cancelledOrEmpty
}

enum CaptureCommandBuilder {
  static func arguments(for request: CaptureRequest) throws -> [String] {
    var arguments: [String] = []

    switch request.mode {
    case .selection:
      arguments.append(contentsOf: ["-i", "-s"])
    case .fullScreen:
      arguments.append("-m")
    case .window:
      arguments.append(contentsOf: ["-i", "-W", "-w"])
    case .repeatLastArea:
      guard let region = request.repeatRegion, region.isUsable else {
        throw CaptureServiceError.missingRepeatRegion
      }
      arguments.append("-R\(region.screencaptureArgumentValue)")
    }

    if request.delaySeconds > 0 {
      arguments.append("-T")
      arguments.append(String(request.delaySeconds))
    }

    arguments.append(request.outputURL.path)
    return arguments
  }
}

final class CaptureService {
  static let shared = CaptureService()

  private init() {}

  func makeTemporaryOutputURL() -> URL {
    let folder = captureScratchFolderURL()
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
      .appendingPathComponent("capture-\(UUID().uuidString)")
      .appendingPathExtension("png")
  }

  func capture(_ request: CaptureRequest, completion: @escaping (Result<URL, CaptureServiceError>) -> Void) {
    let arguments: [String]
    do {
      arguments = try CaptureCommandBuilder.arguments(for: request)
    } catch let error as CaptureServiceError {
      completion(.failure(error))
      return
    } catch {
      completion(.failure(.failedToRun(error.localizedDescription)))
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      Thread.sleep(forTimeInterval: 0.25)

      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
      process.arguments = arguments

      do {
        try process.run()
        process.waitUntilExit()

        let fileExists = FileManager.default.fileExists(atPath: request.outputURL.path)
        DispatchQueue.main.async {
          fileExists ? completion(.success(request.outputURL)) : completion(.failure(.cancelledOrEmpty))
        }
      } catch {
        DispatchQueue.main.async {
          completion(.failure(.failedToRun(error.localizedDescription)))
        }
      }
    }
  }
}

func captureScratchFolderURL(fileManager: FileManager = .default) -> URL {
  fileManager.temporaryDirectory
    .appendingPathComponent("QPARK Shot", isDirectory: true)
    .appendingPathComponent("Capture Scratch", isDirectory: true)
}

final class RegionSelectionController {
  static let shared = RegionSelectionController()

  private var selectionWindow: NSWindow?
  private var completion: ((CaptureRegion?) -> Void)?

  private init() {}

  func selectRegion(completion: @escaping (CaptureRegion?) -> Void) {
    cancel()
    self.completion = completion

    let screenFrame = NSScreen.screens.reduce(CGRect.null) { partial, screen in
      partial.union(screen.frame)
    }
    guard !screenFrame.isNull else {
      completion(nil)
      return
    }

    let view = RegionSelectionView(frame: CGRect(origin: .zero, size: screenFrame.size))
    view.onCancel = { [weak self] in self?.finish(with: nil) }
    view.onComplete = { [weak self, weak view] rect in
      guard let self, let view, let window = view.window else {
        self?.finish(with: nil)
        return
      }
      let windowRect = view.convert(rect, to: nil)
      let screenRect = window.convertToScreen(windowRect)
      self.finish(with: CaptureRegion(rect: screenRect))
    }

    let window = NSWindow(
      contentRect: screenFrame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isOpaque = false
    window.backgroundColor = .clear
    window.level = .screenSaver
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    window.contentView = view
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    selectionWindow = window
  }

  func cancel() {
    selectionWindow?.orderOut(nil)
    selectionWindow = nil
    completion = nil
  }

  private func finish(with region: CaptureRegion?) {
    let callback = completion
    selectionWindow?.orderOut(nil)
    selectionWindow = nil
    completion = nil
    callback?(region)
  }
}

private final class RegionSelectionView: NSView {
  var onComplete: ((CGRect) -> Void)?
  var onCancel: (() -> Void)?

  private var startPoint: CGPoint?
  private var currentPoint: CGPoint?

  override var acceptsFirstResponder: Bool { true }
  override var isFlipped: Bool { true }

  override func viewDidMoveToWindow() {
    window?.makeFirstResponder(self)
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.black.withAlphaComponent(0.32).setFill()
    bounds.fill()

    guard let startPoint, let currentPoint else { return }

    let rect = CGRect(from: startPoint, to: currentPoint).standardized
    NSColor.clear.setFill()
    rect.fill(using: .clear)

    NSColor.white.withAlphaComponent(0.95).setStroke()
    let path = NSBezierPath(rect: rect)
    path.lineWidth = 2
    path.stroke()
  }

  override func mouseDown(with event: NSEvent) {
    startPoint = convert(event.locationInWindow, from: nil)
    currentPoint = startPoint
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    currentPoint = convert(event.locationInWindow, from: nil)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    currentPoint = convert(event.locationInWindow, from: nil)
    guard let startPoint, let currentPoint else {
      onCancel?()
      return
    }

    let rect = CGRect(from: startPoint, to: currentPoint).standardized
    rect.width >= 4 && rect.height >= 4 ? onComplete?(rect) : onCancel?()
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      onCancel?()
    } else {
      super.keyDown(with: event)
    }
  }
}
