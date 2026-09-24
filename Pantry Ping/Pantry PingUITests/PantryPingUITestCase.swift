//
//  PantryPingUITestCase.swift
//  Pantry PingUITests
//

import XCTest

// Shared setup and helpers for every UI test class. Subclasses inherit them.
class PantryPingUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Empty in-memory database, reminders off so no permission alert interrupts,
        // and onboarding treated as done (OnboardingTests covers it separately).
        app.launchArguments = ["-uiTesting", "-remindersEnabled", "NO", "-hasCompletedOnboarding", "YES"]
        app.launch()
    }

    // Rows combine their text for accessibility ("Milk, Fridge, Expires tomorrow"),
    // so find them by how their label starts.
    func row(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    // Any element whose accessibility label contains `text`.
    func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    // Taps `button` until `expected` appears. On a busy simulator the first tap right
    // after launch or an animation is occasionally dropped.
    func tap(_ button: XCUIElement, until expected: XCUIElement, attempts: Int = 3) {
        for _ in 0..<attempts {
            if button.waitForExistence(timeout: 5) { button.tap() }
            if expected.waitForExistence(timeout: 5) { return }
        }
        XCTFail("\(expected) never appeared after tapping \(button)")
    }

    // Scrolls down until `element` is on screen (lists only create visible rows).
    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    // Types into a field after making sure THIS field has keyboard focus (a keyboard
    // already open for the previous field doesn't count), then closes the keyboard with the
    // app's "Done" button — like a person would before moving to a field hidden behind it.
    func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), "\(field) not found")
        for _ in 0..<4 {
            field.tap()
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { break }
        }
        field.typeText(text)
        let done = app.toolbars.buttons["Done"]
        if done.exists && done.isHittable {
            done.tap()
        }
    }

    // Search narrows the list so the row is on screen.
    func search(_ text: String) {
        let field = app.searchFields.firstMatch
        tap(field, until: app.keyboards.firstMatch)
        field.typeText(text)
    }

    // Saves a screenshot into the test results, handy for reviewing the design.
    func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func loadSamples() {
        tap(app.buttons["Try Sample Groceries"], until: row("Milk"))
    }

    // Opens "+" → New Product.
    func openNewProductForm() {
        tap(app.buttons["Add Grocery"].firstMatch, until: app.buttons["New Product"])
        tap(app.buttons["New Product"], until: app.textFields["Product name, e.g. Protein Granola"])
    }

    // A menu-style picker, found by its label (which reads "Unit, servings").
    func picker(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(label),")).firstMatch
    }

    // Picks `option` from a menu-style picker, then confirms the picker now shows it
    // (on a slow simulator a menu tap is occasionally lost).
    func choose(_ option: String, inPicker picker: XCUIElement) {
        let item = app.buttons.matching(NSPredicate(format: "label == %@", option)).firstMatch
        for _ in 0..<3 {
            tap(picker, until: item)
            item.tap()
            sleep(1)
            if picker.label.hasSuffix(", \(option)") { return }
        }
        XCTFail("Picker never showed \(option); it shows \(picker.label)")
    }
}
