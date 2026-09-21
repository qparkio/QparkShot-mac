import Foundation
import ImageIO
import Vision

final class OCRService {
  static let shared = OCRService()
  static let indexVersion = 3

  private let recognitionQueue = DispatchQueue(label: "com.qpark.shot.ocr", qos: .utility)

  private init() {}

  enum OCRResult: Equatable {
    case succeeded(String)
    case noText
    case failed(String)

    var text: String {
      switch self {
      case .succeeded(let text):
        return text
      case .noText, .failed:
        return ""
      }
    }
  }

  func recognizeText(in path: String, completion: @escaping (String) -> Void) {
    recognitionQueue.async {
      let text = Self.recognizeTextSynchronously(in: path)
      DispatchQueue.main.async {
        completion(text)
      }
    }
  }

  func recognize(
    in path: String,
    recognitionLanguages: [String],
    bookmarkData: Data?,
    folders: [StorageFolderCandidate],
    expectedModifiedAt: Date?
  ) async -> OCRResult {
    await withCheckedContinuation { continuation in
      recognitionQueue.async {
        let access = securityScopedImageAccess(url: URL(fileURLWithPath: path), bookmarkData: bookmarkData, folders: folders)
        defer { access.stop() }
        let result = Self.recognizeSynchronously(in: access.url.path, recognitionLanguages: recognitionLanguages)
        let modifiedAt = try? URL(fileURLWithPath: access.url.path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        continuation.resume(returning: modifiedAt == expectedModifiedAt ? result : .failed("source-changed"))
      }
    }
  }

  static func recognizeTextSynchronously(in path: String) -> String {
    recognizeSynchronously(in: path, recognitionLanguages: []).text
  }

  static func recognizeSynchronously(
    in path: String,
    recognitionLanguages: [String]
  ) -> OCRResult {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      return .failed("decode")
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if !recognitionLanguages.isEmpty {
      request.recognitionLanguages = recognitionLanguages
    }

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return .failed(error.localizedDescription)
    }

    let observations = request.results ?? []
    let text = observations
      .compactMap { $0.topCandidates(1).first?.string }
      .joined(separator: "\n")

    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? .noText
      : .succeeded(text)
  }

  static func visionRecognitionLanguages(for languageCodes: [String]) -> [String] {
    let mapped = languageCodes
      .compactMap(AppLanguage.init(rawValue:))
      .compactMap(\.visionRecognitionLanguage)
    let supported = supportedRecognitionLanguages()
    let withFallback = mapped + ["en-US"]
    var seen: Set<String> = []
    return withFallback.filter { language in
      supported.contains(language) && seen.insert(language).inserted
    }
  }

  static func languageSignature(for languageCodes: [String]) -> String {
    visionRecognitionLanguages(for: languageCodes).joined(separator: ",")
  }

  private static func supportedRecognitionLanguages() -> Set<String> {
    let request = VNRecognizeTextRequest()
    let languages = (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
    return Set(languages)
  }
}

/// Serial recognition bounds image memory; replacing a run invalidates its late results.
@MainActor
final class OCRIndexingQueue {
  private var task: Task<Void, Never>?

  func cancel() {
    task?.cancel()
    task = nil
  }

  func start(
    paths: [String],
    recognize: @escaping (String) async -> OCRService.OCRResult,
    started: @escaping (String) -> Void,
    completed: @escaping (String, OCRService.OCRResult) -> Void
  ) {
    cancel()
    task = Task {
      for path in paths {
        guard !Task.isCancelled else { return }
        started(path)
        var result = await recognize(path)
        guard !Task.isCancelled else { return }
        if case .failed = result {
          // One retry per pass; persistent errors remain eligible on the next reload.
          result = await recognize(path)
        }
        guard !Task.isCancelled else { return }
        completed(path, result)
      }
    }
  }
}
