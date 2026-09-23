//
//  InventoryFlowTests.swift
//  Pantry PingUITests
//

import XCTest

// The products → packages → usage path, end to end.
final class InventoryFlowTests: PantryPingUITestCase {

    // Save granola (62 g servings, 5 per box) → 310 g → use 31 g → 279 g / 4.5 servings
    // → buy again without typing the nutrition again.
    func testGranolaProductPackageAndBuyAgain() {
        openNewProductForm()
        type("Quaker Protein Granola", into: app.textFields["Product name, e.g. Protein Granola"])

        tap(app.buttons["Serving & Nutrition"].firstMatch, until: app.textFields["Serving size"])
        type("62", into: app.textFields["Serving size"])
        type("5", into: app.textFields["Servings per package"])
        type("260", into: app.textFields["Calories"])
        type("44", into: app.textFields["Carbohydrates"])
        type("10", into: app.textFields["Protein"])
        type("7", into: app.textFields["Fat"])
        keepScreenshot(named: "New product form")
        app.navigationBars["New Product"].buttons["Save"].tap()

        // The box holds 5 × 62 g = 310 g.
        let granola = row("Quaker Protein Granola")
        XCTAssertTrue(granola.waitForExistence(timeout: 10))
        XCTAssertTrue(granola.label.contains("310 g · 5 servings"), "Row label was: \(granola.label)")
        keepScreenshot(named: "Kitchen with granola")

        // Use 31 g.
        tap(granola, until: app.buttons["Use Some"])
        tap(app.buttons["Use Some"], until: app.textFields["Amount"])
        type("31", into: app.textFields["Amount"])
        choose("g", inPicker: picker("Unit"))
        XCTAssertTrue(element(containing: "Leaves 279 g · 4.5 servings").waitForExistence(timeout: 5))
        keepScreenshot(named: "Use some sheet")
        app.navigationBars["Use Some"].buttons["Save"].tap()

        XCTAssertTrue(element(containing: "279 g · 4.5 servings left").waitForExistence(timeout: 10))
        keepScreenshot(named: "Granola detail after using 31 g")

        // Buy again: only package details are asked for; the 5-serving size is prefilled.
        let buyAgain = app.buttons["Buy Again"]
        scrollTo(buyAgain)
        tap(buyAgain, until: app.navigationBars["Buy Again"])
        XCTAssertTrue(element(containing: "Serving 62 g").exists, "The saved serving should be reused")
        app.navigationBars["Buy Again"].buttons["Save"].tap()

        // Back in the kitchen there are now two separate granola packages.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let packages = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Quaker Protein Granola"))
        XCTAssertTrue(packages.element(boundBy: 1).waitForExistence(timeout: 10))
        XCTAssertTrue(element(containing: "279 g · 4.5 servings").exists)
        XCTAssertTrue(element(containing: "310 g · 5 servings").exists)
        keepScreenshot(named: "Kitchen with two granola packages")
    }
}
