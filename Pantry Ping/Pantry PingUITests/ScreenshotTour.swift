//
//  ScreenshotTour.swift
//  Pantry PingUITests
//

import XCTest

// Visits every main screen with sample data and saves screenshots for design review.
final class ScreenshotTour: PantryPingUITestCase {
    func testTour() {
        loadSamples()
        keepScreenshot(named: "01 Kitchen")

        tap(app.buttons["More"], until: app.buttons["Saved Products"])
        tap(app.buttons["Saved Products"], until: app.navigationBars["Saved Products"])
        keepScreenshot(named: "02 Saved products")
        app.buttons["Done"].tap()
        tap(app.buttons["More"], until: app.buttons["Settings"])
        tap(app.buttons["Settings"], until: app.navigationBars["Settings"])
        keepScreenshot(named: "03 Settings")
        app.buttons["Done"].tap()

        tap(app.buttons["Meals"].firstMatch, until: row("Chicken Rice Bowls"))
        keepScreenshot(named: "04 Meals")
        tap(row("Chicken Rice Bowls"), until: app.buttons["Eat a Portion"])
        keepScreenshot(named: "05 Meal detail")

        tap(app.buttons["Log"].firstMatch, until: app.staticTexts["Food Log"])
        keepScreenshot(named: "06 Log")
        tap(app.buttons["Shopping"].firstMatch, until: app.staticTexts["Shopping List"])
        keepScreenshot(named: "07 Shopping")
        tap(app.buttons["History"].firstMatch, until: app.segmentedControls.buttons["Purchases"])
        keepScreenshot(named: "08 History purchases")

        tap(app.buttons["Kitchen"].firstMatch, until: app.searchFields.firstMatch)
        search("Granola")
        tap(row("Quaker Protein Granola"), until: app.buttons["Use Some"])
        keepScreenshot(named: "09 Granola detail")
        let history = app.staticTexts["History"]
        scrollTo(history)
        keepScreenshot(named: "10 Granola detail history")
    }
}
