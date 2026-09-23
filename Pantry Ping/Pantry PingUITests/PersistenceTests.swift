//
//  PersistenceTests.swift
//  Pantry PingUITests
//

import XCTest

// Data must survive the app being closed and reopened. These tests use a real database
// file (in a temporary folder, separate from real data) instead of the in-memory one.
final class PersistenceTests: PantryPingUITestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestingDiskStore", "-resetStore", "-remindersEnabled", "NO"]
        app.launch()
    }

    func testChangesSurviveAnAppRestart() {
        loadSamples()

        // Use 31 g more granola (samples start at 279 g after 31 g eaten today).
        search("Granola")
        let granola = row("Quaker Protein Granola")
        tap(granola, until: app.buttons["Use Some"])
        tap(app.buttons["Use Some"], until: app.textFields["Amount"])
        type("31", into: app.textFields["Amount"])
        choose("g", inPicker: picker("Unit"))
        app.navigationBars["Use Some"].buttons["Save"].tap()
        XCTAssertTrue(element(containing: "248 g · 4 servings left").waitForExistence(timeout: 10))

        // Leave the app like a person would, then have iOS close it.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.terminate()

        // Relaunch WITHOUT resetting the database.
        app.launchArguments = ["-uiTestingDiskStore", "-remindersEnabled", "NO"]
        app.launch()
        XCTAssertTrue(row("Milk").waitForExistence(timeout: 15), "Sample data should still be there")
        search("Granola")
        let reopened = row("Quaker Protein Granola")
        XCTAssertTrue(reopened.waitForExistence(timeout: 10))
        XCTAssertTrue(reopened.label.contains("248 g · 4 servings"), "Row label was: \(reopened.label)")
        tap(app.buttons["Log"].firstMatch, until: element(containing: "Quaker Protein Granola"))
        keepScreenshot(named: "Food log after restart")
    }
}
