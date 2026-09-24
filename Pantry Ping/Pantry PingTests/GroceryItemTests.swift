//
//  GroceryItemTests.swift
//  Pantry PingTests
//

import Foundation
import SwiftData
import Testing
@testable import Pantry_Ping

@MainActor
struct GroceryItemTests {
    let calendar = TestDates.calendar(timeZone: "America/New_York")

    private func daysFromNow(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: .now)!
    }

    @Test func newItemStoresDatesAtNoonAndKeepsOriginal() {
        let item = GroceryItem(name: "Milk", expirationDate: daysFromNow(2))
        #expect(Calendar.current.component(.hour, from: item.expirationDate!) == 12)
        #expect(item.originalExpirationDate == item.expirationDate)
        #expect(item.status == .active)
        #expect(item.foodState == .fresh)
    }

    @Test func unknownRawValuesFallBackSafely() {
        let item = GroceryItem(name: "Mystery")
        item.categoryRaw = "not-a-category"
        item.storageLocationRaw = "garage"
        item.statusRaw = "???"
        item.foodStateRaw = "pickled"
        #expect(item.category == .other)
        #expect(item.storageLocation == .fridge)
        #expect(item.status == .active)
        #expect(item.foodState == .fresh)
    }

    @Test func resolvingRecordsAndRestoringClearsTheDate() {
        let item = GroceryItem(name: "Eggs")
        item.status = .used
        #expect(item.dateResolved != nil)
        item.status = .active
        #expect(item.dateResolved == nil)
    }

    @Test func freezingMovesToFreezerAndPreservesOriginalDate() {
        let item = GroceryItem(name: "Chicken", expirationDate: daysFromNow(1))
        let original = item.originalExpirationDate
        item.changeFoodState(to: .frozen, newExpirationDate: nil)

        #expect(item.foodState == .frozen)
        #expect(item.storageLocation == .freezer)
        #expect(item.dateFrozen != nil)
        #expect(item.expirationDate == nil)
        #expect(item.originalExpirationDate == original)
        #expect(item.freshnessText(now: .now) == "Frozen today")
    }

    @Test func thawingMovesBackToFridgeWithTheChosenDate() {
        let item = GroceryItem(name: "Chicken", storageLocation: .freezer)
        item.changeFoodState(to: .frozen, newExpirationDate: nil)
        item.changeFoodState(to: .thawed, newExpirationDate: daysFromNow(2))

        #expect(item.storageLocation == .fridge)
        #expect(item.daysRemaining(now: .now) == 2)
        #expect(item.shouldSuggestUseByDate == false)
    }

    @Test func cookedItemWithoutDateGetsANudge() {
        let item = GroceryItem(name: "Rice")
        item.changeFoodState(to: .cooked, newExpirationDate: nil)
        #expect(item.shouldSuggestUseByDate)
    }

    @Test func correctingAFreshItemUpdatesTheOriginalDate() {
        let item = GroceryItem(name: "Yogurt", expirationDate: daysFromNow(3))
        item.setUseByDate(daysFromNow(5), isCorrection: true)
        #expect(item.originalExpirationDate == item.expirationDate)
    }

    @Test func stillHaveItKeepsTheOriginalDate() {
        let item = GroceryItem(name: "Yogurt", expirationDate: daysFromNow(-1))
        let original = item.originalExpirationDate
        item.setUseByDate(daysFromNow(2), isCorrection: false)
        #expect(item.originalExpirationDate == original)
        #expect(item.daysRemaining(now: .now) == 2)
    }

    @Test func sortingPutsMostUrgentFirstAndUndatedLast() {
        let rice = GroceryItem(name: "Rice")
        let cooked = GroceryItem(name: "Soup")
        cooked.changeFoodState(to: .cooked, newExpirationDate: nil)
        let milk = GroceryItem(name: "Milk", expirationDate: daysFromNow(1))
        let berries = GroceryItem(name: "Berries", expirationDate: daysFromNow(-2))
        let eggs = GroceryItem(name: "Eggs", expirationDate: daysFromNow(10))

        let sorted = GroceryItem.sortedByUrgency([rice, eggs, cooked, milk, berries], now: .now)
        // Undated items needing a date (Soup) come before ordinary undated ones (Rice).
        #expect(sorted.map(\.name) == ["Berries", "Milk", "Eggs", "Soup", "Rice"])
    }

    @Test func relativeDayText() {
        let now = TestDates.date(2026, 6, 30, in: calendar)
        func text(_ daysAgo: Int) -> String {
            GroceryItem.relativeDayText(from: calendar.date(byAdding: .day, value: -daysAgo, to: now)!, now: now, calendar: calendar)
        }
        #expect(text(0) == "today")
        #expect(text(1) == "yesterday")
        #expect(text(4) == "4 days ago")
        #expect(text(21) == "3 weeks ago")
    }

    // Round-trip through a real (in-memory) SwiftData store, including the status filter
    // the Home and History screens rely on.
    @Test func persistsAndFiltersByStatus() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV3.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let milk = GroceryItem(name: "Milk", category: .dairyEggs, expirationDate: daysFromNow(1))
        context.insert(milk)
        context.insert(GroceryItem(name: "Rice", storageLocation: .pantry))
        try context.save()

        let activeOnly = FetchDescriptor<GroceryItem>(predicate: #Predicate { $0.statusRaw == "active" })
        #expect(try context.fetch(activeOnly).count == 2)

        milk.status = .used
        try context.save()
        let remaining = try context.fetch(activeOnly)
        #expect(remaining.map(\.name) == ["Rice"])
        #expect(remaining.first?.storageLocation == .pantry)
    }
}
