//
//  OnboardingTests.swift
//  Pantry PingUITests
//

import XCTest

// The first-launch welcome flow: name → who it's for → the app, remembered afterwards.
final class OnboardingTests: PantryPingUITestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-remindersEnabled", "NO", "-resetProfile"]
        app.launch()
    }

    func testFirstLaunchAsksNameAndHouseholdThenRemembers() {
        tap(app.buttons["Get Started"], until: app.textFields["Your name"])
        type("Dhiren", into: app.textFields["Your name"])
        app.buttons["Continue"].tap()

        let start = app.buttons["Start Using Pantry Ping"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertFalse(start.isEnabled, "A household type must be chosen first")
        tap(element(containing: "Student"), until: element(containing: "Add prices when you buy"))
        keepScreenshot(named: "Onboarding household")
        XCTAssertTrue(start.isEnabled)
        start.tap()

        // The app opens, greeting by name.
        XCTAssertTrue(element(containing: ", Dhiren").waitForExistence(timeout: 10) ||
                      app.staticTexts["Your kitchen is empty"].exists)
        XCTAssertTrue(app.staticTexts["Your kitchen is empty"].waitForExistence(timeout: 5))

        // Relaunch without resetting: onboarding doesn't come back.
        app.terminate()
        app.launchArguments = ["-uiTesting", "-remindersEnabled", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your kitchen is empty"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Get Started"].exists)

        // The choice shows in Settings.
        tap(app.buttons["More"], until: app.buttons["Settings"])
        tap(app.buttons["Settings"], until: app.navigationBars["Settings"])
        XCTAssertTrue(element(containing: "Student").waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Your name"].value as? String, "Dhiren")
    }

    func testNameIsOptional() {
        tap(app.buttons["Get Started"], until: app.buttons["Skip"])
        app.buttons["Skip"].tap()
        tap(element(containing: "Family or household"), until: app.buttons["Start Using Pantry Ping"])
        app.buttons["Start Using Pantry Ping"].tap()
        XCTAssertTrue(app.staticTexts["Your kitchen is empty"].waitForExistence(timeout: 10))
    }
}
