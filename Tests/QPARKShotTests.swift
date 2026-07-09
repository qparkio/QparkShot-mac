import AppKit
import XCTest
@testable import QPARK_Shot

final class QPARKShotTests: XCTestCase {
  func testAppSettingsDefaultsIncludeNewFeatureSections() {
    let settings = AppSettings()

    XCTAssertEqual(settings.export.selectedPresetID, ExportPreset.watermarked.id)
    XCTAssertEqual(settings.export.filenameTemplate, "{date}_{time}_{preset}")
    XCTAssertEqual(settings.export.defaultQuickAction, "edit")
    XCTAssertTrue(settings.gallery.ocrEnabled)
    XCTAssertTrue(settings.gallery.searchIndexEnabled)
    XCTAssertNil(settings.capture.lastRegion)
  }

  func testLegacyStorageSettingsDecodeWithoutSecurityBookmark() throws {
    let json = """
    {
      "cleanup": {
        "mode": "never",
        "includeSavedFiles": false,
        "durationSeconds": 86400,
        "saveDirectory": "/tmp/qpark-legacy"
      },
      "watermark": {
        "logo": {
          "enabled": true,
          "path": "/tmp/logo.png",
          "size": 120,
          "opacity": 0.5,
          "positionMode": "bottomRight"
        }
      }
    }
    """
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

    XCTAssertEqual(settings.cleanup.saveDirectory, "/tmp/qpark-legacy")
    XCTAssertNil(settings.cleanup.saveDirectoryBookmarkData)
    XCTAssertEqual(settings.watermark.logo.path, "/tmp/logo.png")
    XCTAssertNil(settings.watermark.logo.bookmarkData)
  }

  func testSupportedLocalizationLanguageCodesAreStableBCP47Values() {
    let codes = AppLanguage.allCases.map(\.rawValue)

    XCTAssertEqual(
      codes,
      ["en", "es", "zh-Hans", "ja", "fr", "ru", "uk", "kk", "ar", "de", "it", "pt-BR"]
    )
    XCTAssertEqual(AppLanguage.arabic.layoutDirection, .rightToLeft)
    XCTAssertEqual(AppLanguage.english.layoutDirection, .leftToRight)
  }

  func testLocalizationCoverageExistsForEverySupportedLanguage() {
    for key in LocalizationController.requiredKeys {
      for language in AppLanguage.allCases {
        XCTAssertTrue(
          LocalizationController.hasTranslation(for: key, language: language),
          "Missing \(language.rawValue) translation for \(key)"
        )
      }
    }
  }

  func testPreferredLanguageMappingUsesProductDefaults() {
    XCTAssertEqual(AppLanguage.preferredDefault(from: ["zh-Hant-HK"]), .chineseSimplified)
    XCTAssertEqual(AppLanguage.preferredDefault(from: ["pt-PT"]), .portugueseBrazil)
    XCTAssertEqual(AppLanguage.preferredDefault(from: ["de-DE"]), .german)
    XCTAssertEqual(AppLanguage.preferredDefault(from: ["unsupported"]), .english)
  }

  func testLocalizationSettingsSanitizeUnsupportedCodes() {
    let settings = LocalizationSettings(
      appLanguageCode: "pt",
      textRecognitionLanguageCodes: ["ru", "xx", "pt-BR", "ru"]
    )

    XCTAssertEqual(settings.appLanguageCode, "en")
    XCTAssertEqual(settings.textRecognitionLanguageCodes, ["ru", "pt-BR"])
    XCTAssertEqual(LocalizationSettings(textRecognitionLanguageCodes: []).textRecognitionLanguageCodes, ["en"])
  }

  func testOCRLanguageCodesMapToVisionBCP47Values() {
    let languages = OCRService.visionRecognitionLanguages(for: ["ru", "en", "kk", "pt-BR"])

    XCTAssertTrue(languages.contains("ru-RU"))
    XCTAssertTrue(languages.contains("en-US"))
    XCTAssertTrue(languages.contains("pt-BR"))
    XCTAssertFalse(languages.contains("ru"))
    XCTAssertFalse(languages.contains("en"))
    XCTAssertFalse(languages.contains("kk"))
    XCTAssertEqual(OCRService.languageSignature(for: ["ru", "en", "kk"]), "ru-RU,en-US")
  }

  func testFilenameTemplateReplacesTokensAndSanitizesUnsafeCharacters() {
    let date = Date(timeIntervalSince1970: 1_772_305_234.123)
    let filename = FileNameTemplate.makeFilename(
      template: "{date}/{time}:{preset}:{uuid}",
      preset: .support,
      date: date,
      uuid: "ABC12345"
    )

    XCTAssertFalse(filename.contains("/"))
    XCTAssertFalse(filename.contains(":"))
    XCTAssertTrue(filename.contains("support"))
    XCTAssertTrue(filename.contains("ABC12345"))
  }

  func testCaptureCommandBuilderArguments() throws {
    let outputURL = URL(fileURLWithPath: "/tmp/qpark-test.png")
    let region = CaptureRegion(x: 10, y: 20, width: 300, height: 200)

    let selection = try CaptureCommandBuilder.arguments(for: CaptureRequest(mode: .selection, outputURL: outputURL))
    XCTAssertEqual(selection, ["-i", "-s", outputURL.path])

    let fullScreen = try CaptureCommandBuilder.arguments(for: CaptureRequest(mode: .fullScreen, delaySeconds: 3, outputURL: outputURL))
    XCTAssertEqual(fullScreen, ["-m", "-T", "3", outputURL.path])

    let window = try CaptureCommandBuilder.arguments(for: CaptureRequest(mode: .window, outputURL: outputURL))
    XCTAssertEqual(window, ["-i", "-W", "-w", outputURL.path])

    let repeatArea = try CaptureCommandBuilder.arguments(
      for: CaptureRequest(mode: .repeatLastArea, outputURL: outputURL, repeatRegion: region)
    )
    XCTAssertEqual(repeatArea, ["-R10,20,300,200", outputURL.path])
  }

  func testCaptureScratchAndExportScratchRootsAreSeparated() {
    let captureRoot = captureScratchFolderURL().path
    let exportRoot = storageFolderURL(isTemporary: true).path

    XCTAssertTrue(captureRoot.contains("Capture Scratch"))
    XCTAssertTrue(exportRoot.contains("Export Scratch"))
    XCTAssertNotEqual(captureRoot, exportRoot)
  }

  func testCustomGalleryDirectoryKeepsDefaultFallbackRoots() {
    let customPath = "/tmp/qpark-custom-gallery"
    let urls = galleryStorageFolderURLs(saveDirectory: customPath)

    XCTAssertEqual(urls.first?.path, customPath)
    XCTAssertTrue(urls.contains { $0.path.contains("Pictures/QPARK Shot") })
  }

  func testQueueCleanupOnlyDeletesOwnedScratchFiles() throws {
    ShotQueueStore.shared.clearAll()
    let fileManager = FileManager.default
    let externalURL = fileManager.temporaryDirectory.appendingPathComponent("qpark-external-\(UUID().uuidString).png")
    let captureURL = captureScratchFolderURL().appendingPathComponent("qpark-owned-\(UUID().uuidString).png")

    try fileManager.createDirectory(at: captureURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("external".utf8).write(to: externalURL)
    try Data("owned".utf8).write(to: captureURL)
    defer {
      try? fileManager.removeItem(at: externalURL)
      try? fileManager.removeItem(at: captureURL)
      ShotQueueStore.shared.clearAll()
    }

    _ = ShotQueueStore.shared.enqueue(path: externalURL.path)
    _ = ShotQueueStore.shared.enqueue(path: captureURL.path)
    ShotQueueStore.shared.clearAll()

    XCTAssertTrue(fileManager.fileExists(atPath: externalURL.path))
    XCTAssertFalse(fileManager.fileExists(atPath: captureURL.path))
  }

  func testConcurrentTemporaryExportsDoNotOverwriteEachOther() {
    let image = NSImage(size: CGSize(width: 48, height: 32))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 48, height: 32).fill()
    image.unlockFocus()
    guard let pngData = ExportService.shared.pngData(from: image) else {
      XCTFail("Could not encode test PNG")
      return
    }

    let group = DispatchGroup()
    let lock = NSLock()
    var paths: [String] = []

    for _ in 0..<8 {
      group.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        let path = ExportService.shared.save(
          pngData: pngData,
          isTemporary: true,
          preset: .clean,
          filenameTemplate: "race-test"
        )
        lock.lock()
        if let path {
          paths.append(path)
        }
        lock.unlock()
        group.leave()
      }
    }

    XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
    defer {
      for path in paths {
        try? FileManager.default.removeItem(atPath: path)
      }
    }
    XCTAssertEqual(paths.count, 8)
    XCTAssertEqual(Set(paths).count, 8)
  }

  func testGalleryIndexSearchesFilenameTagsAndOCRText() {
    let suiteName = "qpark-shot-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = GalleryIndexStore(defaults: defaults)
    let path = "/tmp/Checkout.png"
    store.updateExistingPaths([path])
    store.setTags(["bug", "checkout"], for: path)
    store.updateOCRText(
      "Payment failed at confirmation",
      for: path,
      languageSignature: "en-US",
      engineVersion: OCRService.indexVersion
    )

    XCTAssertEqual(store.pathsMatching("checkout payment", in: [path]), [path])
    XCTAssertEqual(store.pathsMatching("missing", in: [path]), [])
    XCTAssertEqual(store.entry(for: path).ocrLanguageSignature, "en-US")
    XCTAssertEqual(store.entry(for: path).ocrEngineVersion, OCRService.indexVersion)
  }

  func testOCRRecognizesGeneratedEnglishTextImage() throws {
    let image = NSImage(size: CGSize(width: 520, height: 160))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 520, height: 160).fill()
    let text = "HELLO 123"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.boldSystemFont(ofSize: 54),
      .foregroundColor: NSColor.black
    ]
    text.draw(at: CGPoint(x: 40, y: 48), withAttributes: attributes)
    image.unlockFocus()

    let data = try XCTUnwrap(ExportService.shared.pngData(from: image))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("qpark-ocr-\(UUID().uuidString)")
      .appendingPathExtension("png")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let result = OCRService.recognizeSynchronously(
      in: url.path,
      recognitionLanguages: ["en-US"]
    )
    guard case .succeeded(let recognizedText) = result else {
      XCTFail("Expected OCR success, got \(result)")
      return
    }
    XCTAssertTrue(recognizedText.uppercased().contains("HELLO"))
  }

  func testAnnotatedRendererKeepsImageSize() {
    let image = NSImage(size: CGSize(width: 120, height: 80))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 120, height: 80).fill()
    image.unlockFocus()

    let annotations = [
      Annotation(type: .redact, color: .black, strokeWidth: 4, rect: CGRect(x: 10, y: 10, width: 30, height: 20)),
      Annotation(type: .callout, color: .red, strokeWidth: 4, points: [CGPoint(x: 70, y: 40)], calloutNumber: 1)
    ]

    let rendered = renderAnnotatedImage(
      image: image,
      annotations: annotations,
      cropRect: nil,
      watermark: .disabled
    )

    XCTAssertEqual(rendered?.size.width, 120)
    XCTAssertEqual(rendered?.size.height, 80)
  }

  func testWatermarkedExportPresetDrawsVisibleWatermark() throws {
    let image = NSImage(size: CGSize(width: 220, height: 120))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 220, height: 120).fill()
    image.unlockFocus()

    let watermark = WatermarkRenderSettings(
      textEnabled: true,
      text: "WM",
      textColor: "#FF0000",
      logoEnabled: false,
      logoPath: "",
      opacity: 1,
      logoSize: 120,
      position: "center",
      layoutMode: "single",
      spacing: 150,
      tilePattern: "aligned",
      tileRandomness: 0
    )

    let clean = try XCTUnwrap(
      ExportService.shared.render(
        ExportContext(
          image: image,
          annotations: [],
          cropRect: nil,
          preset: .clean,
          watermark: watermark
        )
      )
    )
    let watermarked = try XCTUnwrap(
      ExportService.shared.render(
        ExportContext(
          image: image,
          annotations: [],
          cropRect: nil,
          preset: .watermarked,
          watermark: watermark
        )
      )
    )

    XCTAssertEqual(redPixelCount(in: clean), 0)
    XCTAssertGreaterThan(redPixelCount(in: watermarked), 20)
  }

  func testTiledWatermarkedExportCanBeEncodedAndSaved() throws {
    let image = NSImage(size: CGSize(width: 640, height: 360))
    image.lockFocus()
    NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 640, height: 360).fill()
    NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.45, alpha: 1).setFill()
    NSRect(x: 42, y: 90, width: 420, height: 76).fill()
    image.unlockFocus()

    let watermark = WatermarkRenderSettings(
      textEnabled: true,
      text: "QPARK.IO",
      textColor: "#FF4A1A",
      logoEnabled: false,
      logoPath: "",
      opacity: 0.35,
      logoSize: 200,
      position: "bottomRight",
      layoutMode: "tiled",
      spacing: 80,
      tilePattern: "brick",
      tileRandomness: 1
    )
    let rendered = try XCTUnwrap(
      ExportService.shared.render(
        ExportContext(
          image: image,
          annotations: [],
          cropRect: nil,
          preset: .watermarked,
          watermark: watermark
        )
      )
    )
    let data = try XCTUnwrap(ExportService.shared.pngData(from: rendered))
    XCTAssertGreaterThan(data.count, 100)

    let path = try XCTUnwrap(
      ExportService.shared.save(
        pngData: data,
        isTemporary: true,
        preset: .watermarked,
        filenameTemplate: "tiled-watermark-{uuid}"
      )
    )
    defer { try? FileManager.default.removeItem(atPath: path) }
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
  }

  func testRecentWindowIncludesExactSevenDayBoundary() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let boundary = now.addingTimeInterval(-7 * 24 * 60 * 60)

    XCTAssertTrue(isWithinRecentWindow(boundary, now: now))
    XCTAssertTrue(isWithinRecentWindow(now, now: now))
    XCTAssertFalse(isWithinRecentWindow(boundary.addingTimeInterval(-0.001), now: now))
    XCTAssertFalse(isWithinRecentWindow(now.addingTimeInterval(0.001), now: now))
  }

  func testMissingRelinkAndForgetPreserveMetadata() throws {
    let suiteName = "qpark-shot-index-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = GalleryIndexStore(defaults: defaults)
    let oldPath = "/tmp/original.png"
    let newURL = URL(fileURLWithPath: "/tmp/relinked.png")
    let createdAt = Date(timeIntervalSince1970: 1234)

    store.reconcile(existingFiles: [GalleryFileSnapshot(path: oldPath, createdAt: createdAt)])
    store.toggleFavorite(path: oldPath)
    store.setTags(["billing", "urgent"], for: oldPath)
    store.updateOCRText("Invoice 42", for: oldPath, languageSignature: "en-US", engineVersion: 1)
    store.reconcile(existingFiles: [], now: createdAt.addingTimeInterval(10))

    XCTAssertEqual(store.missingEntries.map(\.path), [oldPath])
    let relinked = try XCTUnwrap(store.relink(
      from: oldPath,
      to: newURL,
      createdAt: createdAt,
      bookmarkData: Data([1, 2, 3])
    ))
    XCTAssertTrue(relinked.favorite)
    XCTAssertEqual(relinked.tags, ["billing", "urgent"])
    XCTAssertEqual(relinked.ocrText, "Invoice 42")
    XCTAssertNil(relinked.missingSince)

    store.forget(path: newURL.path)
    XCTAssertNil(store.entries[newURL.path])
  }

  func testLegacyGalleryEntryDecodesNewOptionalFieldsSafely() throws {
    let json = """
    {
      "path":"/tmp/legacy.png",
      "fileName":"legacy.png",
      "favorite":true,
      "tags":["keep"],
      "ocrText":"legacy OCR",
      "updatedAt":0
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let entry = try decoder.decode(GalleryIndexEntry.self, from: Data(json.utf8))

    XCTAssertTrue(entry.favorite)
    XCTAssertEqual(entry.tags, ["keep"])
    XCTAssertEqual(entry.ocrText, "legacy OCR")
    XCTAssertNil(entry.lastKnownCreatedAt)
    XCTAssertNil(entry.lastSeenAt)
    XCTAssertNil(entry.missingSince)
  }

  func testQueuePanelVisibilityHonorsSettingAndCount() {
    XCTAssertFalse(shouldShowSessionStrip(isEnabled: false, itemCount: 5))
    XCTAssertFalse(shouldShowSessionStrip(isEnabled: true, itemCount: 1))
    XCTAssertTrue(shouldShowSessionStrip(isEnabled: true, itemCount: 2))
  }

  func testShortcutValidationRejectsMissingModifierUnsupportedKeyAndDuplicate() {
    XCTAssertEqual(
      HotkeySettings(enabled: true, key: "A", modifiers: ["shift"]).validationError(),
      .missingPrimaryModifier
    )
    XCTAssertEqual(
      HotkeySettings(enabled: true, key: "F1", modifiers: ["command"]).validationError(),
      .unsupportedKey
    )
    let first = HotkeySettings(enabled: true, key: "c", modifiers: ["shift", "command"])
    let duplicate = HotkeySettings(enabled: true, key: "C", modifiers: ["command", "shift"])
    XCTAssertEqual(first.validationError(comparedWith: duplicate), .duplicate)
  }

  func testSettingsChangesExposeOnlyTargetedEffects() {
    XCTAssertEqual(SettingsChange.watermark.effects, [])
    XCTAssertEqual(SettingsChange.capture.effects, [])
    XCTAssertEqual(SettingsChange.appearance.effects, .appearance)
    XCTAssertEqual(SettingsChange.shortcuts.effects, [.hotkeys, .localizedChrome])
    XCTAssertEqual(SettingsChange.cleanup.effects, .cleanup)
    XCTAssertFalse(SettingsChange.localization.effects.contains(.hotkeys))
  }

  func testCleanupStaysInsideOwnedRootAndHonorsActiveFiles() async throws {
    let fileManager = FileManager.default
    let base = fileManager.temporaryDirectory.appendingPathComponent("qpark-cleanup-\(UUID().uuidString)")
    let root = base.appendingPathComponent("owned")
    let outside = base.appendingPathComponent("outside.png")
    let old = root.appendingPathComponent("old.png")
    let active = root.appendingPathComponent("active.png")
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    for url in [outside, old, active] { try Data("x".utf8).write(to: url) }
    let oldDate = Date(timeIntervalSinceNow: -7200)
    for url in [outside, old, active] {
      try fileManager.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
    }
    defer { try? fileManager.removeItem(at: base) }

    let report = await CleanupService().run(
      policy: CleanupPolicy(mode: .afterDuration, maxAge: 3600, includeSavedFiles: false),
      galleryEntries: [],
      activePaths: [active.path],
      temporaryRoots: [root],
      savedRoots: []
    )

    XCTAssertEqual(report.deletedTemporaryPaths.map { URL(fileURLWithPath: $0).lastPathComponent }, ["old.png"])
    XCTAssertFalse(fileManager.fileExists(atPath: old.path))
    XCTAssertTrue(fileManager.fileExists(atPath: active.path))
    XCTAssertTrue(fileManager.fileExists(atPath: outside.path))
  }

  func testCleanupRejectsSymlinkTraversal() async throws {
    let fileManager = FileManager.default
    let base = fileManager.temporaryDirectory.appendingPathComponent("qpark-cleanup-link-\(UUID().uuidString)")
    let root = base.appendingPathComponent("owned")
    let outside = base.appendingPathComponent("outside.png")
    let link = root.appendingPathComponent("escape.png")
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("outside".utf8).write(to: outside)
    try fileManager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: outside.path)
    try fileManager.createSymbolicLink(at: link, withDestinationURL: outside)
    defer { try? fileManager.removeItem(at: base) }

    let report = await CleanupService().run(
      policy: CleanupPolicy(mode: .afterDuration, maxAge: 3600, includeSavedFiles: false),
      galleryEntries: [],
      activePaths: [],
      temporaryRoots: [root],
      savedRoots: []
    )

    XCTAssertTrue(report.deletedTemporaryPaths.isEmpty)
    XCTAssertTrue(fileManager.fileExists(atPath: outside.path))
  }

  func testCleanupRechecksAgeImmediatelyBeforeMutation() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("qpark-cleanup-race-\(UUID().uuidString)")
    let file = root.appendingPathComponent("export.png")
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("writing".utf8).write(to: file)
    try fileManager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: file.path)
    defer { try? fileManager.removeItem(at: root) }

    let service = CleanupService(beforeMutation: { candidate in
      try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: candidate.path)
    })
    let report = await service.run(
      policy: CleanupPolicy(mode: .afterDuration, maxAge: 3600, includeSavedFiles: false),
      galleryEntries: [],
      activePaths: [],
      temporaryRoots: [root],
      savedRoots: []
    )

    XCTAssertTrue(report.deletedTemporaryPaths.isEmpty)
    XCTAssertTrue(fileManager.fileExists(atPath: file.path))
  }

  func testCleanupTrashesSavedFilesButExcludesFavoriteAndActive() async throws {
    let fileManager = FileManager.default
    let base = fileManager.temporaryDirectory.appendingPathComponent("qpark-cleanup-saved-\(UUID().uuidString)")
    let savedRoot = base.appendingPathComponent("saved")
    let trashRoot = base.appendingPathComponent("trash")
    try fileManager.createDirectory(at: savedRoot, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: trashRoot, withIntermediateDirectories: true)
    let removable = savedRoot.appendingPathComponent("removable.png")
    let favorite = savedRoot.appendingPathComponent("favorite.png")
    let active = savedRoot.appendingPathComponent("active.png")
    for url in [removable, favorite, active] {
      try Data("saved".utf8).write(to: url)
      try fileManager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: url.path)
    }
    defer { try? fileManager.removeItem(at: base) }

    let service = CleanupService(trashOperation: { url in
      try FileManager.default.moveItem(at: url, to: trashRoot.appendingPathComponent(url.lastPathComponent))
    })
    let entries = [
      GalleryIndexEntry(path: removable.path, fileName: removable.lastPathComponent),
      GalleryIndexEntry(path: favorite.path, fileName: favorite.lastPathComponent, favorite: true),
      GalleryIndexEntry(path: active.path, fileName: active.lastPathComponent)
    ]
    let report = await service.run(
      policy: CleanupPolicy(mode: .afterDuration, maxAge: 3600, includeSavedFiles: true),
      galleryEntries: entries,
      activePaths: [active.path],
      temporaryRoots: [],
      savedRoots: [StorageFolderCandidate(url: savedRoot, bookmarkData: nil)]
    )

    XCTAssertEqual(report.trashedSavedPaths, [removable.path])
    XCTAssertTrue(fileManager.fileExists(atPath: trashRoot.appendingPathComponent(removable.lastPathComponent).path))
    XCTAssertTrue(fileManager.fileExists(atPath: favorite.path))
    XCTAssertTrue(fileManager.fileExists(atPath: active.path))
  }

  func testCleanupCanRunRepeatedlyWithoutDuplicateMutations() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("qpark-cleanup-repeat-\(UUID().uuidString)")
    let file = root.appendingPathComponent("old.png")
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: file)
    try fileManager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: file.path)
    defer { try? fileManager.removeItem(at: root) }
    let service = CleanupService()
    let policy = CleanupPolicy(mode: .afterDuration, maxAge: 3600, includeSavedFiles: false)

    let first = await service.run(
      policy: policy,
      galleryEntries: [],
      activePaths: [],
      temporaryRoots: [root],
      savedRoots: []
    )
    let second = await service.run(
      policy: policy,
      galleryEntries: [],
      activePaths: [],
      temporaryRoots: [root],
      savedRoots: []
    )

    XCTAssertEqual(first.deletedTemporaryPaths.count, 1)
    XCTAssertFalse(second.changedAnything)
    XCTAssertTrue(second.failures.isEmpty)
  }

  private func redPixelCount(in image: NSImage) -> Int {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
      return 0
    }

    var count = 0
    for y in 0..<rep.pixelsHigh {
      for x in 0..<rep.pixelsWide {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        if color.redComponent > 0.7,
           color.greenComponent < 0.35,
           color.blueComponent < 0.35,
           color.alphaComponent > 0.5 {
          count += 1
        }
      }
    }
    return count
  }
}
