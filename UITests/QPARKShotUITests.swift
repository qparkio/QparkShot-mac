import XCTest
import AppKit

final class QPARKShotUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testSidebarSearchAndKeyboardOpen() {
    let app = launch(scenario: "library")
    XCTAssertTrue(app.buttons["workspace.capture"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["sidebar.recent"].exists)

    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 3))
    search.click()
    search.typeText("QPARK")

    let card = app.buttons["shot.QPARK UI Test.png"]
    XCTAssertTrue(card.waitForExistence(timeout: 3))
    card.click()
    app.typeKey(.space, modifierFlags: [])
    XCTAssertTrue(card.exists)
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout: 3))
  }

  func testReviewCopyPrimaryAction() {
    let app = launch(scenario: "review")
    let copy = app.buttons["review.copy"]
    XCTAssertTrue(copy.waitForExistence(timeout: 5))
    let changeCount = NSPasteboard.general.changeCount
    copy.click()
    let copied = NSPredicate { _, _ in NSPasteboard.general.changeCount > changeCount }
    expectation(for: copied, evaluatedWith: nil)
    waitForExpectations(timeout: 5)
    XCTAssertNotNil(NSImage(pasteboard: .general))
  }

  func testEditorSaveAndDirtySessionConfirmation() {
    let app = launch(scenario: "editor")
    let save = app.buttons["editor.save"]
    XCTAssertTrue(save.waitForExistence(timeout: 5))

    let clear = app.buttons["session.clear"]
    XCTAssertTrue(clear.waitForExistence(timeout: 3))
    clear.click()
    XCTAssertTrue(app.buttons["session.clear.confirm"].waitForExistence(timeout: 3))
    app.typeKey(.escape, modifierFlags: [])
    save.click()
    XCTAssertTrue(app.staticTexts["Saved final image."].waitForExistence(timeout: 5))
    app.descendants(matching: .any)["sidebar.library"].firstMatch.click()
    let saved = NSPredicate { _, _ in
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "shot.")).count >= 2
    }
    expectation(for: saved, evaluatedWith: nil)
    waitForExpectations(timeout: 5)
  }

  func testShortcutRecorderInSettings() {
    let app = launch(scenario: "library")
    XCTAssertTrue(app.buttons["shot.QPARK UI Test.png"].waitForExistence(timeout: 5))
    app.buttons["workspace.settings"].click()
    let capturePane = app.descendants(matching: .any)["settings.capture"].firstMatch
    XCTAssertTrue(capturePane.waitForExistence(timeout: 3))
    capturePane.click()

    let recorder = app.buttons["settings.shortcut.selection"].firstMatch
    XCTAssertTrue(recorder.waitForExistence(timeout: 3))
    recorder.click()
    app.typeKey("k", modifierFlags: [.command, .option])
    expectation(for: NSPredicate(format: "value == %@", "⌥⌘K"), evaluatedWith: recorder)
    waitForExpectations(timeout: 5)
  }

  func testPermissionStateExposesRecoveryAction() {
    let app = launch(scenario: "permission")
    XCTAssertTrue(app.buttons["permission.openSettings"].waitForExistence(timeout: 5))
  }

  func testErrorStateExposesRetryAction() {
    let app = launch(scenario: "error")
    XCTAssertTrue(app.buttons["error.retry"].waitForExistence(timeout: 5))
  }

  func testCropUndoRedoAndSaveAtMinimumSize() {
    let app = launch(scenario: "editor", size: "920x620")
    let clearCrop = app.buttons["editor.clearCrop"]
    XCTAssertTrue(clearCrop.waitForExistence(timeout: 5))
    XCTAssertTrue(clearCrop.isEnabled)
    expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["editor.save"])
    waitForExpectations(timeout: 5)
    app.buttons["editor.undo"].click()
    expectation(for: NSPredicate(format: "enabled == false"), evaluatedWith: clearCrop)
    waitForExpectations(timeout: 5)
    app.buttons["editor.redo"].click()
    expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: clearCrop)
    waitForExpectations(timeout: 5)
    let save = app.buttons["editor.save"]
    XCTAssertTrue(save.isHittable)
    XCTAssertLessThanOrEqual(app.windows.firstMatch.frame.width, 921)
    let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    screenshot.name = "editor-920x620"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  func testMissingEditorImageAllowsRetryAndBack() {
    let app = launch(scenario: "broken-editor")
    let retry = app.buttons["editor.retry"]
    XCTAssertTrue(retry.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["editor.save"].isEnabled)
    retry.click()
    XCTAssertTrue(retry.waitForExistence(timeout: 5))
    let back = app.buttons["editor.back"]
    XCTAssertTrue(back.isEnabled)
    back.click()
    XCTAssertFalse(app.buttons["editor.save"].exists)
  }

  func testRapidSessionSwitchKeepsCorrectImage() {
    let app = launch(scenario: "multi-editor")
    let first = app.buttons["session.item.QPARK UI Test.png"]
    let second = app.buttons["session.item.Portrait.png"]
    XCTAssertTrue(second.waitForExistence(timeout: 5))
    for _ in 0..<3 { second.click(); first.click() }
    second.click()
    let canvas = app.descendants(matching: .any)["editor.canvas"].firstMatch
    let portrait = NSPredicate(format: "label ENDSWITH %@", "300 × 600")
    expectation(for: portrait, evaluatedWith: canvas)
    waitForExpectations(timeout: 5)
    XCTAssertTrue(app.buttons["editor.save"].isEnabled)
    attachWindow(app.windows.firstMatch, name: "editor-portrait-session")
  }

  func testReviewAndSettingsLayoutsAcrossLanguages() {
    for language in ["en", "ru", "ar", "de", "es", "zh-Hans", "ja", "fr", "uk", "kk", "it", "pt-BR"] {
      let app = launch(scenario: "review", size: "920x620", language: language, theme: language == "ru" ? "dark" : "light")
      XCTAssertTrue(app.buttons["review.copy"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.buttons["review.copy"].isHittable)
      attachWindow(app.windows.firstMatch, name: "review-\(language)-920x620")
      app.buttons["workspace.settings"].click()
      for pane in ["general", "capture", "export", "watermark", "storage"] {
        let row = app.descendants(matching: .any)["settings.\(pane)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        if ["ru", "ar", "de"].contains(language) {
          attachWindow(app.windows.firstMatch, name: "settings-\(pane)-\(language)")
        }
      }
      app.terminate()
    }
  }

  func testLibraryAtLargerSize() {
    let app = launch(scenario: "library", size: "1280x800")
    XCTAssertTrue(app.buttons["shot.QPARK UI Test.png"].waitForExistence(timeout: 5))
    attachWindow(app.windows.firstMatch, name: "library-1280x800")
  }

  private func attachWindow(_ window: XCUIElement, name: String) {
    let screenshot = XCTAttachment(screenshot: window.screenshot())
    screenshot.name = name
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  private func launch(scenario: String, size: String = "1280x800", language: String = "en", theme: String = "light") -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-scenario", scenario]
    app.launchEnvironment["QPARK_TEST_WINDOW_SIZE"] = size
    app.launchEnvironment["QPARK_TEST_LANGUAGE"] = language
    app.launchEnvironment["QPARK_TEST_THEME"] = theme
    app.launchEnvironment["QPARK_TEST_SETTINGS_MIN"] = "1"
    app.launch()
    app.activate()
    let width = Double(size.split(separator: "x")[0])!
    expectation(for: NSPredicate { _, _ in abs(app.windows.firstMatch.frame.width - width) < 2 }, evaluatedWith: nil)
    waitForExpectations(timeout: 5)
    return app
  }
}
