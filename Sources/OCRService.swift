import Foundation
import ImageIO
import Vision

final class OCRService {
  static let shared = OCRService()
  static let indexVersion = 2

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
    DispatchQueue.global(qos: .utility).async {
      let text = Self.recognizeTextSynchronously(in: path)
      DispatchQueue.main.async {
        completion(text)
      }
    }
  }

  func recognize(in path: String, completion: @escaping (OCRResult) -> Void) {
    let languages = Self.visionRecognitionLanguages(
      for: SettingsStore.shared.textRecognitionLanguageCodes
    )

    DispatchQueue.global(qos: .utility).async {
      let result = Self.recognizeSynchronously(in: path, recognitionLanguages: languages)
      DispatchQueue.main.async {
        completion(result)
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
