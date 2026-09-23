//
//  PantryPingFlowTests.swift
//  Pantry PingUITests
//

import XCTest

// End-to-end checks of the core kitchen flows, tapping through the real app.
// UI tests still use XCTest: Swift Testing doesn't drive the UI yet.
final class PantryPingFlowTests: PantryPingUITestCase {

    func testEmptyStateIsShownOnFirstLaunch() {
        XCTAssertTrue(app.staticTexts["Your kitchen is empty"].waitForExistence(timeout: 5))
    }

    func testAddGroceryShowsCountdown() {
        openNewProductForm()
        type("Oat Milk", into: app.textFields["Product name, e.g. Protein Granola"])
        let quickPick = app.buttons["+3 days"]
        scrollTo(quickPick)
        quickPick.tap()
        app.navigationBars["New Product"].buttons["Save"].tap()

        let newRow = row("Oat Milk")
        XCTAssertTrue(newRow.waitForExistence(timeout: 10))
        XCTAssertTrue(newRow.label.contains("3 days left"), "Row label was: \(newRow.label)")
        XCTAssertTrue(app.staticTexts["Use Soon"].exists)
    }

    func testSaveIsDisabledWithoutAName() {
        openNewProductForm()
        let save = app.navigationBars["New Product"].buttons["Save"]
        XCTAssertTrue(save.exists)
        XCTAssertFalse(save.isEnabled)
    }

    func testSampleGroceriesAreGroupedByUrgency() {
        loadSamples()
        keepScreenshot(named: "Kitchen with sample groceries")
        XCTAssertTrue(app.staticTexts["Expired"].exists)
        XCTAssertTrue(app.staticTexts["Needs Attention"].exists)
        XCTAssertTrue(row("Strawberries").label.contains("Expired yesterday"))
        XCTAssertTrue(row("Milk").label.contains("Expires tomorrow"))

        // Lists only create rows that are on screen, so filter to the Freezer to reach the chicken.
        let chicken = row("Chicken Breast")
        tap(app.segmentedControls.buttons["Freezer"], until: chicken)
        XCTAssertTrue(chicken.label.contains("Frozen 4 days ago"), "Row label was: \(chicken.label)")
    }

    func testFinishedMovesItemToHistory() {
        loadSamples()
        tap(row("Milk"), until: app.buttons["Finished"])
        app.buttons["Finished"].tap()

        XCTAssertTrue(row("Spinach").waitForExistence(timeout: 5))
        XCTAssertFalse(row("Milk").exists)

        tap(app.buttons["History"].firstMatch, until: app.segmentedControls.buttons["Finished"])
        let historyRow = row("Milk")
        tap(app.segmentedControls.buttons["Finished"], until: historyRow)
        XCTAssertTrue(historyRow.label.contains("Finished today"), "History label was: \(historyRow.label)")
    }

    func testFreezeMovesItemToFreezer() {
        loadSamples()
        search("Yogurt")
        tap(row("Greek Yogurt"), until: app.buttons["Freeze"])
        let sheetBar = app.navigationBars["Freeze Greek Yogurt"]
        tap(app.buttons["Freeze"], until: sheetBar)
        keepScreenshot(named: "Freeze sheet")
        sheetBar.buttons["Freeze"].tap()

        XCTAssertTrue(element(containing: "Frozen today").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Thaw"].exists)
    }

    func testDeleteFromDetailRemovesItem() {
        loadSamples()
        search("Rice")
        tap(row("Rice"), until: app.buttons["Use Some"])
        let delete = app.buttons["Delete Grocery"]
        scrollTo(delete)
        delete.tap()

        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        // Back on the list, the search for "Rice" now finds nothing.
        XCTAssertTrue(app.staticTexts["No Results for \u{201C}Rice\u{201D}"].waitForExistence(timeout: 10))
        XCTAssertFalse(row("Rice").exists)
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
