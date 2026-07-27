//
//  AppStoreCodesUITests.swift
//  AppStoreCodesUITests
//
//  Created by Matteo Comisso on 08/12/2025.
//

import XCTest

final class AppStoreCodesUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testRightClickingAnImportOpensRenameSheet() throws {
        #if os(macOS)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()

        let importButton = app.buttons["import-Original Filename"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3))
        app.activate()
        importButton.rightClick()

        let renameMenuItem = app.menuItems["Rename Import..."]
        XCTAssertTrue(renameMenuItem.waitForExistence(timeout: 2))
        renameMenuItem.click()

        let nameField = app.textFields["rename-import-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("Lifetime")
        app.buttons["Save"].click()

        XCTAssertTrue(app.buttons["import-Lifetime"].waitForExistence(timeout: 2))
        #else
        throw XCTSkip("Context-menu rename is a macOS-only interaction.")
        #endif
    }

    @MainActor
    func testTrackingSettingsAreReachableAndRequireConfiguration() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-trackingAPIBaseURL", "",
            "-trackInteraction", "NO",
        ]
        app.launch()
        app.activate()

        #if os(iOS)
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(
            settingsButton.waitForExistence(timeout: 5),
            "The main toolbar should expose an accessible Settings button."
        )
        XCTAssertTrue(settingsButton.isHittable)
        settingsButton.tap()
        #elseif os(macOS)
        app.typeKey(",", modifierFlags: .command)
        #endif

        let trackingTab = app.buttons["Tracking"]
        XCTAssertTrue(
            trackingTab.waitForExistence(timeout: 5),
            "Settings should expose the Tracking tab."
        )
        trackingTab.tap()

        XCTAssertTrue(app.textFields["API domain"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.secureTextFields["API token"].exists)
        XCTAssertTrue(app.buttons["Test Connection"].exists)

        let trackingToggle = app.switches["Track interaction"]
        XCTAssertTrue(trackingToggle.waitForExistence(timeout: 3))
        XCTAssertFalse(
            trackingToggle.isEnabled,
            "Tracking must remain disabled until the API domain and stored token are valid."
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
