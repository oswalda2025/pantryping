//
//  PantryPingFlowTests.swift
//  Pantry PingUITests
//

import XCTest

// End-to-end checks that tap through the real app, like a user would.
// UI tests still use XCTest: Swift Testing doesn't drive the UI yet.
final class PantryPingFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Empty in-memory database, and reminders off so no permission alert interrupts.
        app.launchArguments = ["-uiTesting", "-remindersEnabled", "NO"]
        app.launch()
    }

    // Rows combine their text for accessibility ("Milk, Fridge, Expires tomorrow"),
    // so find them by how their label starts.
    private func row(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    // Taps `button` until `expected` appears. On a busy simulator the first tap right
    // after launch or an animation is occasionally dropped.
    private func tap(_ button: XCUIElement, until expected: XCUIElement, attempts: Int = 3) {
        for _ in 0..<attempts {
            if button.waitForExistence(timeout: 5) { button.tap() }
            if expected.waitForExistence(timeout: 5) { return }
        }
        XCTFail("\(expected) never appeared after tapping \(button)")
    }

    private func openAddForm() {
        tap(app.buttons["Add Grocery"].firstMatch, until: app.textFields["Name, e.g. Milk"])
    }

    // Search narrows the list so the row is on screen (lists only create visible rows).
    private func search(_ text: String) {
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText(text)
    }

    private func loadSamples() {
        tap(app.buttons["Try Sample Groceries"], until: row("Milk"))
    }

    func testEmptyStateIsShownOnFirstLaunch() {
        XCTAssertTrue(app.staticTexts["Your kitchen is empty"].waitForExistence(timeout: 5))
    }

    func testAddGroceryShowsCountdown() {
        openAddForm()
        let nameField = app.textFields["Name, e.g. Milk"]
        nameField.tap()
        nameField.typeText("Oat Milk")
        app.buttons["+3 days"].tap()
        app.navigationBars["Add Grocery"].buttons["Save"].tap()

        let newRow = row("Oat Milk")
        XCTAssertTrue(newRow.waitForExistence(timeout: 5))
        XCTAssertTrue(newRow.label.contains("3 days left"), "Row label was: \(newRow.label)")
        XCTAssertTrue(app.staticTexts["Use Soon"].exists)
    }

    func testSaveIsDisabledWithoutAName() {
        openAddForm()
        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.exists)
        XCTAssertFalse(save.isEnabled)
    }

    func testSampleGroceriesAreGroupedByUrgency() {
        loadSamples()
        XCTAssertTrue(app.staticTexts["Expired"].exists)
        XCTAssertTrue(app.staticTexts["Needs Attention"].exists)
        XCTAssertTrue(row("Strawberries").label.contains("Expired yesterday"))
        XCTAssertTrue(row("Milk").label.contains("Expires tomorrow"))

        // Lists only create rows that are on screen, so filter to the Freezer to reach the chicken.
        let chicken = row("Chicken Breast")
        tap(app.segmentedControls.buttons["Freezer"], until: chicken)
        XCTAssertTrue(chicken.label.contains("Frozen 4 days ago"), "Row label was: \(chicken.label)")
    }

    func testMarkAsUsedMovesItemToHistory() {
        loadSamples()
        tap(row("Milk"), until: app.buttons["Mark as Used"])
        app.buttons["Mark as Used"].tap()

        XCTAssertTrue(row("Spinach").waitForExistence(timeout: 5))
        XCTAssertFalse(row("Milk").exists)

        let historyRow = row("Milk")
        tap(app.buttons["History"].firstMatch, until: historyRow)
        XCTAssertTrue(historyRow.label.contains("Used today"), "History label was: \(historyRow.label)")
    }

    func testFreezeMovesItemToFreezer() {
        loadSamples()
        search("Yogurt")
        tap(row("Greek Yogurt"), until: app.buttons["Freeze"])
        let sheetBar = app.navigationBars["Freeze Greek Yogurt"]
        tap(app.buttons["Freeze"], until: sheetBar)
        sheetBar.buttons["Freeze"].tap()

        XCTAssertTrue(app.staticTexts["Frozen today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Thaw"].exists)
    }

    func testLocationFilterAndSearch() {
        loadSamples()
        tap(app.segmentedControls.buttons["Pantry"], until: row("Rice"))
        XCTAssertFalse(row("Milk").exists)

        tap(app.segmentedControls.buttons["All"], until: row("Milk"))
        search("egg")
        XCTAssertTrue(row("Eggs").waitForExistence(timeout: 5))
        XCTAssertFalse(row("Spinach").exists)
    }
}
