//
//  EdgeCaseTests.swift
//  Pantry PingUITests
//

import XCTest

// Empty screens, invalid input, missing nutrition, and throwing food away.
final class EdgeCaseTests: PantryPingUITestCase {

    func testEveryTabShowsAHelpfulEmptyState() {
        XCTAssertTrue(app.staticTexts["Your kitchen is empty"].waitForExistence(timeout: 5))

        tap(app.buttons["Meals"].firstMatch, until: app.staticTexts["No prepared meals"])
        tap(app.buttons["Log"].firstMatch, until: app.staticTexts["Nothing logged today"])
        tap(app.buttons["Shopping"].firstMatch, until: app.staticTexts["Your list is empty"])
        tap(app.buttons["History"].firstMatch, until: app.staticTexts["No purchases yet"])
        tap(app.segmentedControls.buttons["Finished"], until: app.staticTexts["Nothing finished yet"])
    }

    func testInvalidAmountsAreRejectedAndMissingMacrosSayNotEntered() {
        loadSamples()
        // Milk has no nutrition entered and holds 1 carton.
        tap(row("Milk"), until: app.buttons["Use Some"])
        tap(app.buttons["Use Some"], until: app.textFields["Amount"])
        let save = app.navigationBars["Use Some"].buttons["Save"]

        type("5", into: app.textFields["Amount"])
        XCTAssertTrue(element(containing: "more than what's left").waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)

        type(XCUIKeyboardKey.delete.rawValue + "0", into: app.textFields["Amount"])
        XCTAssertTrue(element(containing: "greater than zero").waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)

        type(XCUIKeyboardKey.delete.rawValue + "0.5", into: app.textFields["Amount"])
        XCTAssertTrue(element(containing: "Leaves 0.5 pieces").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Nutrition not entered for this product").exists)
        XCTAssertTrue(save.isEnabled)
        keepScreenshot(named: "Use some with missing macros")
    }

    func testThrowingAwayMovesItemToHistory() {
        loadSamples()
        tap(row("Strawberries"), until: app.buttons["Threw Away"])
        app.buttons["Threw Away"].tap()
        XCTAssertTrue(row("Spinach").waitForExistence(timeout: 5))
        XCTAssertFalse(row("Strawberries").exists)

        tap(app.buttons["History"].firstMatch, until: app.segmentedControls.buttons["Finished"])
        let tossed = row("Strawberries")
        tap(app.segmentedControls.buttons["Finished"], until: tossed)
        XCTAssertTrue(tossed.label.contains("Thrown away today"), "History label was: \(tossed.label)")
    }
}
