import XCTest

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
    card.typeKey(.space, modifierFlags: [])
    XCTAssertTrue(card.exists)
    card.doubleClick()
    XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout: 3))
  }

  func testReviewCopyPrimaryAction() {
    let app = launch(scenario: "review")
    let copy = app.buttons["review.copy"]
    XCTAssertTrue(copy.waitForExistence(timeout: 5))
    copy.click()
    XCTAssertTrue(copy.exists)
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
  }

  func testShortcutRecorderInSettings() {
    let app = launch(scenario: "library")
    app.buttons["workspace.settings"].firstMatch.click()
    XCTAssertTrue(app.windows.count >= 2)
    let capturePane = app.descendants(matching: .any)["settings.capture"].firstMatch
    XCTAssertTrue(capturePane.waitForExistence(timeout: 3))
    capturePane.click()

    let recorder = app.buttons["settings.shortcut.selection"].firstMatch
    XCTAssertTrue(recorder.waitForExistence(timeout: 3))
    recorder.click()
    app.typeKey("k", modifierFlags: [.command, .option])
    XCTAssertTrue(recorder.exists)
  }

  func testPermissionStateExposesRecoveryAction() {
    let app = launch(scenario: "permission")
    XCTAssertTrue(app.buttons["permission.openSettings"].waitForExistence(timeout: 5))
  }

  func testErrorStateExposesRetryAction() {
    let app = launch(scenario: "error")
    XCTAssertTrue(app.buttons["error.retry"].waitForExistence(timeout: 5))
  }

  private func launch(scenario: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test-scenario", scenario]
    app.launch()
    return app
  }
}
