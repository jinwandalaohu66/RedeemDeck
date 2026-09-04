import XCTest

final class RedeemDeckUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppRowUsesQuantityAlertThenPushesCanonicalResult() throws {
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["Codes"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.count, 0)
        XCTAssertEqual(app.searchFields.count, 0)
        XCTAssertTrue(app.staticTexts["1/1 · 1 type"].exists)

        app.buttons["UI Test App"].tap()

        let alert = app.alerts["Get Codes"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.textFields["Quantity"].exists)
        XCTAssertTrue(alert.buttons["Get"].exists)
        XCTAssertTrue(app.navigationBars["Codes"].exists)
        alert.buttons["Get"].tap()

        XCTAssertTrue(app.navigationBars["Retrieved 1 Code"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Codes"].exists)
        XCTAssertTrue(app.buttons["Links"].exists)
        XCTAssertTrue(app.buttons["Poster"].exists)
        XCTAssertTrue(app.staticTexts["TESTCODE123"].exists)
        XCTAssertFalse(app.staticTexts["••••-E123"].exists)
        XCTAssertFalse(app.buttons["Share"].exists)
        XCTAssertFalse(app.staticTexts["UI Test App"].exists)
        XCTAssertFalse(app.staticTexts["UI Test Product · Launch Offer"].exists)
        XCTAssertFalse(app.staticTexts["1 pending"].exists)

        app.buttons["Copy"].tap()
        XCTAssertTrue(app.staticTexts["Copied 1 Code."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Undo"].exists)
    }

    @MainActor
    func testPendingRetrievalPushesBackIntoSameResultPage() throws {
        let app = launchApp()
        app.buttons["UI Test App"].tap()
        app.alerts["Get Codes"].buttons["Get"].tap()
        XCTAssertTrue(app.navigationBars["Retrieved 1 Code"].waitForExistence(timeout: 5))
        app.navigationBars["Retrieved 1 Code"].buttons["Codes"].tap()

        XCTAssertTrue(app.staticTexts["Continue Retrieval"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 pending"].exists)
        app.buttons["Continue UI Test App retrieval"].tap()

        XCTAssertTrue(app.navigationBars["Retrieved 1 Code"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Return to Inventory"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["More"].exists)
    }

    @MainActor
    func testPosterStackSwipesItsTopCardAndPreservesPosition() throws {
        let app = launchApp(additionalArguments: ["--ui-testing-poster-deck"])
        app.buttons["UI Test App"].tap()
        let quantity = app.alerts["Get Codes"].textFields["Quantity"]
        quantity.tap()
        quantity.typeText("\u{8}3")
        app.alerts["Get Codes"].buttons["Get"].tap()
        XCTAssertTrue(app.navigationBars["Retrieved 3 Codes"].waitForExistence(timeout: 5))

        app.buttons["Poster"].tap()

        let poster = app.images["Redemption Poster"].firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["QR code 1 of 3"].exists)
        poster.swipeLeft()
        XCTAssertTrue(app.staticTexts["QR code 2 of 3"].waitForExistence(timeout: 3))

        app.segmentedControls.buttons["Codes"].tap()
        app.segmentedControls.buttons["Poster"].tap()
        XCTAssertTrue(app.staticTexts["QR code 2 of 3"].exists)
        XCTAssertTrue(app.buttons["Edit Greeting"].exists)
        XCTAssertTrue(app.buttons["Save 3"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Redemption Poster"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testSettingsKeepOnlyUsefulLocalTools() throws {
        let app = launchApp()
        app.buttons["Settings"].tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["Hide Full Codes"].exists)
        XCTAssertFalse(app.switches["Clear Copied Codes Automatically"].exists)
        XCTAssertFalse(app.switches["Require Device Authentication"].exists)
        XCTAssertTrue(app.switches["Expiration Alerts"].exists)
        XCTAssertTrue(app.buttons["Backup and Restore"].exists)
        XCTAssertTrue(app.buttons["Archived Items"].exists)

        let localStorageValue = app.staticTexts["Storage, On This Device"]
        if !localStorageValue.exists { app.swipeUp() }
        XCTAssertTrue(localStorageValue.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Open Source Project"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Privacy Policy"].exists)
        XCTAssertTrue(app.buttons["Support"].exists)
        XCTAssertFalse(
            app.staticTexts[
                "RedeemDeck does not require an account or CloudKit. Export a backup before deleting the app or changing devices."
            ].exists
        )
    }

    @MainActor
    func testLibraryProvidesNativeActionsAndArchiveAlert() throws {
        let app = launchApp()
        let row = app.cells.containing(.staticText, identifier: "UI Test App").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        row.swipeLeft()
        XCTAssertTrue(app.buttons["Manage"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Edit"].exists)
        XCTAssertTrue(app.buttons["Archive"].exists)
        app.buttons["Archive"].tap()
        XCTAssertTrue(app.alerts["Archive this app?"].waitForExistence(timeout: 2))
        app.alerts["Archive this app?"].buttons["Cancel"].tap()

        let restoredRow = app.cells.containing(.staticText, identifier: "UI Test App").firstMatch
        restoredRow.swipeLeft()
        app.buttons["Manage"].tap()
        XCTAssertTrue(app.navigationBars["UI Test App"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Launch Offer"].exists)

        let categoryRow = app.cells.containing(.staticText, identifier: "Launch Offer").firstMatch
        categoryRow.tap()
        XCTAssertTrue(app.staticTexts["TESTCODE123"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Get Codes"].exists)

        let codeRow = app.cells.containing(.staticText, identifier: "TESTCODE123").firstMatch
        codeRow.tap()
        XCTAssertTrue(app.navigationBars["Code Details"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Get Codes"].exists)
    }

    @MainActor
    func testDarkModeSwipeActionsUseSystemContrast() throws {
        let app = launchApp(interfaceStyle: "Dark")
        let row = app.cells.containing(.staticText, identifier: "UI Test App").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        row.swipeLeft()
        XCTAssertTrue(app.buttons["Manage"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Edit"].exists)
        XCTAssertTrue(app.buttons["Archive"].exists)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Dark Mode Swipe Actions"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testSimplifiedChineseLocalizationLoads() throws {
        let app = launchApp(language: "zh-Hans", locale: "zh_CN")

        XCTAssertTrue(app.navigationBars["兑换码"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.count, 0)
        XCTAssertEqual(app.searchFields.count, 0)
        app.buttons["UI Test App"].tap()
        XCTAssertTrue(app.alerts["获取兑换码"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.alerts["获取兑换码"].buttons["获取"].exists)
        app.alerts["获取兑换码"].buttons["获取"].tap()
        XCTAssertTrue(app.navigationBars["已获取 1 个兑换码"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["TESTCODE123"].exists)
    }

    @MainActor
    private func launchApp(
        language: String = "en",
        locale: String = "en_US",
        interfaceStyle: String? = nil,
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = [
            "--ui-testing",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
        ]
        if let interfaceStyle {
            arguments += ["-AppleInterfaceStyle", interfaceStyle]
        }
        app.launchArguments = arguments + additionalArguments
        app.launch()
        app.activate()
        return app
    }
}
