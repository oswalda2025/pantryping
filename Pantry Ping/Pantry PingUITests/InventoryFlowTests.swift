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

    // Shopping list → Buy → purchase form → the item joins the kitchen and leaves the list.
    func testShoppingListItemMovesIntoThePurchaseFlow() {
        tap(app.buttons["Shopping"].firstMatch, until: app.textFields["Add an item"])
        type("Bananas", into: app.textFields["Add an item"])
        app.buttons["Add"].tap()

        tap(app.buttons["Buy Bananas"], until: app.navigationBars["New Product"])
        let name = app.textFields["Product name, e.g. Protein Granola"]
        XCTAssertEqual(name.value as? String, "Bananas")
        app.navigationBars["New Product"].buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 10))
        tap(app.buttons["Kitchen"].firstMatch, until: row("Bananas"))
    }

    // Meal prep from a kitchen package → the package shrinks → eat a portion → it's in the log.
    func testMealPrepUsesInventoryAndEatingIsLogged() {
        loadSamples()
        tap(app.buttons["Meals"].firstMatch, until: app.buttons["New Meal Prep"].firstMatch)
        tap(app.buttons["New Meal Prep"].firstMatch, until: app.textFields["Meal name, e.g. Chicken Rice Bowls"])
        type("Rice Salad", into: app.textFields["Meal name, e.g. Chicken Rice Bowls"])

        tap(app.buttons["Add Ingredient"], until: app.buttons["From Kitchen"])
        search("Rice")
        let riceOption = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rice,")).firstMatch
        tap(riceOption, until: picker("Unit"))
        type("90", into: app.textFields["Amount"])
        choose("g", inPicker: picker("Unit"))
        app.buttons.matching(NSPredicate(format: "label == %@", "Add")).firstMatch.tap()

        type("2", into: app.textFields["Portions"])
        keepScreenshot(named: "Meal prep form")
        app.navigationBars["New Meal Prep"].buttons["Save"].tap()

        let meal = row("Rice Salad")
        XCTAssertTrue(meal.waitForExistence(timeout: 10))
        XCTAssertTrue(meal.label.contains("2 portions left"), "Meal label was: \(meal.label)")

        tap(meal, until: app.buttons["Eat a Portion"])
        tap(app.buttons["Eat a Portion"], until: app.navigationBars["Eat Rice Salad"])
        app.navigationBars["Eat Rice Salad"].buttons["Save"].tap()
        XCTAssertTrue(element(containing: "1 portion left").waitForExistence(timeout: 10))
        keepScreenshot(named: "Meal detail after eating")

        tap(app.buttons["Log"].firstMatch, until: element(containing: "Rice Salad"))
        keepScreenshot(named: "Food log")

        // The rice package lost exactly 90 g (1000 − 180 for the sample meal − 90).
        tap(app.buttons["Kitchen"].firstMatch, until: app.searchFields.firstMatch)
        search("Rice")
        XCTAssertTrue(element(containing: "730 g").waitForExistence(timeout: 10))
    }
}
