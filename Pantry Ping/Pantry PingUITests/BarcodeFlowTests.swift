//
//  BarcodeFlowTests.swift
//  Pantry PingUITests
//

import XCTest

// Scan (typed, since the Simulator has no camera) → pre-filled product → saved →
// scanning again recognizes it. Uses a stubbed lookup instead of the internet.
final class BarcodeFlowTests: PantryPingUITestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-remindersEnabled", "NO", "-hasCompletedOnboarding", "YES", "-stubFoodLookup"]
        app.launch()
    }

    private func lookUp(_ code: String) {
        tap(app.buttons["Add Grocery"].firstMatch, until: app.buttons["Scan Barcode"])
        tap(app.buttons["Scan Barcode"], until: app.textFields["Barcode number"])
        type(code, into: app.textFields["Barcode number"])
        app.buttons["Look Up"].tap()
    }

    func testScannedProductIsPrefilledSavedAndRecognizedNextTime() {
        lookUp("016000275287")
        XCTAssertTrue(element(containing: "Found in Open Food Facts").waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["Product name, e.g. Protein Granola"].value as? String, "Cheerios")
        keepScreenshot(named: "Scanned product form")
        app.navigationBars["New Product"].buttons["Save"].tap()

        // 510 g box of 39 g servings.
        let cheerios = row("Cheerios")
        XCTAssertTrue(cheerios.waitForExistence(timeout: 10))
        XCTAssertTrue(cheerios.label.contains("510 g · 13.08 servings"), "Row label was: \(cheerios.label)")

        // Scanning the same barcode again goes straight to Buy Again.
        lookUp("016000275287")
        XCTAssertTrue(app.navigationBars["Buy Again"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(containing: "Serving 39 g").exists)
    }

    func testUnknownBarcodeStillLetsYouAddTheProduct() {
        lookUp("000000000017")
        XCTAssertTrue(element(containing: "wasn't found").waitForExistence(timeout: 10))
        type("Mystery Snack", into: app.textFields["Product name, e.g. Protein Granola"])
        app.navigationBars["New Product"].buttons["Save"].tap()
        XCTAssertTrue(row("Mystery Snack").waitForExistence(timeout: 10))

        // Now it's recognized.
        lookUp("000000000017")
        XCTAssertTrue(app.navigationBars["Buy Again"].waitForExistence(timeout: 10))
    }
}
