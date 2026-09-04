import XCTest

final class AppStoreScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEnglishAppStoreScreenshots() throws {
        try captureStoreScreenshots(
            language: "en",
            locale: "en_US",
            homeTitle: "Codes",
            alertTitle: "Get Codes",
            categoryName: "50% Off · 3 Months",
            resultTitle: "Retrieved 3 Codes",
            linksTitle: "Links",
            posterTitle: "Poster",
            posterAccessibilityLabel: "Redemption Poster",
            sourceTitle: "Open Source Project",
            suffix: "en"
        )
    }

    @MainActor
    func testSimplifiedChineseAppStoreScreenshots() throws {
        try captureStoreScreenshots(
            language: "zh-Hans",
            locale: "zh_CN",
            homeTitle: "兑换码",
            alertTitle: "获取兑换码",
            categoryName: "五折 · 3 个月",
            resultTitle: "已获取 3 个兑换码",
            linksTitle: "链接",
            posterTitle: "海报",
            posterAccessibilityLabel: "兑换海报",
            sourceTitle: "开源项目",
            suffix: "zh-Hans"
        )
    }

    @MainActor
    private func captureStoreScreenshots(
        language: String,
        locale: String,
        homeTitle: String,
        alertTitle: String,
        categoryName: String,
        resultTitle: String,
        linksTitle: String,
        posterTitle: String,
        posterAccessibilityLabel: String,
        sourceTitle: String,
        suffix: String
    ) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--app-store-screenshots",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-AppleInterfaceStyle", "Light",
            "-librarySortOrder", "name",
        ]
        app.launch()
        app.activate()

        XCTAssertTrue(app.navigationBars[homeTitle].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["PythonIDE"].waitForExistence(timeout: 20))
        capture(app, name: "01-library-\(suffix)")

        app.buttons["PythonIDE"].tap()
        let alert = app.alerts[alertTitle]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let quantity = alert.textFields.firstMatch
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        quantity.tap()
        quantity.typeText("\u{8}3")
        capture(app, name: "02-quantity-\(suffix)")

        let category = alert.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", categoryName)
        ).firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.tap()

        XCTAssertTrue(app.navigationBars[resultTitle].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["RDPY50000000015"].waitForExistence(timeout: 10))
        capture(app, name: "03-codes-\(suffix)")

        app.segmentedControls.buttons[linksTitle].tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "apps.apple.com/redeem")
            ).firstMatch.waitForExistence(timeout: 10)
        )
        capture(app, name: "04-links-\(suffix)")

        app.segmentedControls.buttons[posterTitle].tap()
        XCTAssertTrue(
            app.images[posterAccessibilityLabel].firstMatch.waitForExistence(timeout: 30)
        )
        capture(app, name: "05-posters-\(suffix)")

        app.navigationBars[resultTitle].buttons[homeTitle].tap()
        XCTAssertTrue(app.navigationBars[homeTitle].waitForExistence(timeout: 10))
        app.buttons[language == "zh-Hans" ? "设置" : "Settings"].tap()
        XCTAssertTrue(app.navigationBars[language == "zh-Hans" ? "设置" : "Settings"].waitForExistence(timeout: 10))
        let source = app.descendants(matching: .any)[sourceTitle].firstMatch
        for _ in 0..<6 where !source.exists || !source.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        capture(app, name: "06-open-source-\(suffix)")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
