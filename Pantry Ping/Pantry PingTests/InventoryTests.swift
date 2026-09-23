//
//  InventoryTests.swift
//  Pantry PingTests
//

import Foundation
import SwiftData
import Testing
@testable import Pantry_Ping

// Quantities, conversions, packages, and usage.
@MainActor
struct InventoryTests {
    // Each test gets its own throwaway in-memory database.
    let context: ModelContext

    init() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    // "Quaker Protein Granola": 62 g servings, 5 per box, 260 kcal / 44 g carbs / 10 g protein / 7 g fat.
    private func makeGranola() -> Product {
        let product = Product(name: "Quaker Protein Granola", category: .dryCanned)
        product.servingSize = 62
        product.servingUnit = .gram
        product.servingsPerPackage = 5
        product.nutrition = NutritionFacts(calories: 260, carbs: 44, protein: 10, fat: 7)
        context.insert(product)
        return product
    }

    private func buyBox(of product: Product, expiring days: Int? = nil) throws -> GroceryItem {
        let expiry = days.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: .now) }
        let package = try product.makePackage(amount: 5, unit: .serving, purchaseDate: .now, price: Decimal(string: "4.99"),
                                              expirationDate: expiry, storageLocation: .pantry)
        context.insert(package)
        return package
    }

    // MARK: - Conversions

    @Test func convertsServingsAndGramsUsingTheLabel() {
        let converter = QuantityConverter(baseUnit: .gram, servingSize: 62, servingUnit: .gram)
        #expect(converter.toBase(5, from: .serving) == 310)
        #expect(converter.toBase(31, from: .gram) == 31)
        #expect(converter.servings(fromBase: 279) == 4.5)
        #expect(abs((converter.toBase(1, from: .ounce) ?? 0) - 28.349523125) < 0.000001)
        #expect(converter.enterableUnits == [.serving, .gram, .kilogram, .ounce, .pound])
    }

    @Test func neverInventsAConversionBetweenWeightAndVolume() {
        let converter = QuantityConverter(baseUnit: .gram, servingSize: 62, servingUnit: .gram)
        #expect(converter.toBase(1, from: .cup) == nil)
        #expect(converter.toBase(10, from: .milliliter) == nil)
    }

    @Test func withoutAServingSizeGramsCantBecomeServings() {
        let converter = QuantityConverter(baseUnit: .serving, servingSize: nil, servingUnit: nil)
        #expect(converter.toBase(31, from: .gram) == nil)
        #expect(converter.toBase(2, from: .serving) == 2)
        #expect(converter.enterableUnits == [.serving])
    }

    @Test func servingPackageConvertsOnceTheProductHasAServingSize() {
        let converter = QuantityConverter(baseUnit: .serving, servingSize: 62, servingUnit: .gram)
        #expect(converter.toBase(31, from: .gram) == 0.5)
    }

    // MARK: - The granola path

    @Test func granolaBoxHolds310gAndUsing31gLeaves279g() throws {
        let box = try buyBox(of: makeGranola())
        #expect(box.quantityUnit == .gram)
        #expect(box.startingAmountMilli == 310_000)
        #expect(box.remainingText == "310 g · 5 servings")

        let entry = try box.use(try box.milli(for: 31, unit: .gram), reason: .ate)
        #expect(box.remainingAmountMilli == 279_000)
        #expect(box.remainingServings == 4.5)
        #expect(box.remainingText == "279 g · 4.5 servings")
        // Half a serving of 260 kcal.
        #expect(entry.calories == 130)
        #expect(entry.protein == 5)
    }

    @Test func repeatedPartialUsesLandExactlyOnZeroAndFinishThePackage() throws {
        let box = try buyBox(of: makeGranola())
        for _ in 0..<10 {
            try box.use(try box.milli(for: 31, unit: .gram), reason: .ate)
        }
        #expect(box.remainingAmountMilli == 0)
        #expect(box.status == .used)
    }

    @Test func fractionalServingsAreHandled() throws {
        let box = try buyBox(of: makeGranola())
        try box.use(try box.milli(for: 0.25, unit: .serving), reason: .ate)
        #expect(box.remainingAmountMilli == 294_500)
        #expect(box.remainingText == "294.5 g · 4.75 servings")
    }

    @Test func cannotUseMoreThanRemainsOrANonPositiveAmount() throws {
        let box = try buyBox(of: makeGranola())
        #expect(throws: InventoryError.self) { try box.use(311_000, reason: .ate) }
        #expect(throws: InventoryError.invalidAmount) { try box.use(0, reason: .ate) }
        #expect(throws: InventoryError.invalidAmount) { try box.milli(for: -5, unit: .gram) }
        #expect(box.remainingAmountMilli == 310_000)
        #expect((box.usageEntries ?? []).isEmpty)
    }

    @Test func finishedPackagesRefuseFurtherUse() throws {
        let box = try buyBox(of: makeGranola())
        box.finish()
        #expect(throws: InventoryError.notActive) { try box.use(1000, reason: .ate) }
    }

    // MARK: - Separate packages and buying again

    @Test func buyingAgainCreatesASeparatePackageAndReusesDetails() throws {
        let granola = makeGranola()
        let first = try buyBox(of: granola, expiring: 30)
        try first.use(31_000, reason: .ate)
        let second = try buyBox(of: granola, expiring: 10)

        #expect(first !== second)
        #expect(first.remainingAmountMilli == 279_000)
        #expect(second.remainingAmountMilli == 310_000)
        #expect(second.product?.calories == 260)
        #expect(granola.packages?.count == 2)
        // The package expiring first is suggested first.
        #expect(granola.activePackagesByExpiry.first === second)
    }

    @Test func packageEnteredInOuncesConvertsToGrams() throws {
        let granola = makeGranola()
        let box = try granola.makePackage(amount: 10, unit: .ounce, purchaseDate: .now, price: nil,
                                          expirationDate: nil, storageLocation: .pantry)
        #expect(box.quantityUnit == .gram)
        #expect(box.startingAmountMilli == Quantity.milli(283.49523125))
    }

    @Test func mismatchedPackageUnitIsRejected() {
        let granola = makeGranola()
        #expect(throws: InventoryError.self) {
            _ = try granola.makePackage(amount: 1, unit: .liter, purchaseDate: .now, price: nil,
                                        expirationDate: nil, storageLocation: .pantry)
        }
    }

    // MARK: - Optional nutrition

    @Test func missingNutritionIsNotEnteredNotZero() throws {
        let milk = Product(name: "Milk")
        context.insert(milk)
        let carton = try milk.makePackage(amount: 1, unit: .piece, purchaseDate: .now, price: nil,
                                          expirationDate: nil, storageLocation: .fridge)
        let entry = try carton.use(500, reason: .ate)
        #expect(entry.nutrition.isEmpty)
        #expect(NutritionFormat.calories(entry.calories) == "not entered")
    }

    @Test func totalsMarkMissingValuesInsteadOfCountingZero() {
        var total = NutritionTotal()
        total.add(NutritionFacts(calories: 260, carbs: 44, protein: nil, fat: 7))
        total.add(NutritionFacts(calories: 260, carbs: nil, protein: nil, fat: nil))
        total.add(.empty)
        #expect(total.calories.text(unit: "kcal", digits: 0) == "520+ kcal (1 not entered)")
        #expect(total.protein.text(unit: "g", digits: 1) == "not entered")
        #expect(total.completeFacts.calories == nil)

        var complete = NutritionTotal()
        complete.add(NutritionFacts(calories: 100))
        complete.add(NutritionFacts(calories: 30))
        #expect(complete.calories.text(unit: "kcal", digits: 0) == "130 kcal")
        #expect(complete.completeFacts.calories == 130)
    }

    // MARK: - Food log

    @Test func onlyAteEntriesCountTowardTheFoodLog() throws {
        let box = try buyBox(of: makeGranola())
        try box.use(31_000, reason: .ate)
        try box.use(62_000, reason: .mealPrep)
        try box.use(10_000, reason: .other)
        try context.save()

        let eaten = try context.fetch(FetchDescriptor<UsageEntry>(predicate: #Predicate { $0.reasonRaw == "ate" }))
        #expect(eaten.count == 1)
        #expect(eaten.first?.calories == 130)
    }

    @Test func undoPutsTheAmountBackAndReopensAnEmptiedPackage() throws {
        let box = try buyBox(of: makeGranola())
        let entry = try box.use(310_000, reason: .ate)
        #expect(box.status == .used)

        entry.undo(in: context)
        #expect(box.remainingAmountMilli == 310_000)
        #expect(box.status == .active)
    }

    // MARK: - Reminders

    @Test func finishedItemsStopGeneratingReminders() throws {
        let granola = makeGranola()
        let kept = try buyBox(of: granola, expiring: 2)
        let finished = try buyBox(of: granola, expiring: 2)
        finished.finish()

        let items = ExpirationReminders.items(from: [kept, finished], meals: [])
        #expect(items.count == 1)
        let plan = ExpirationReminders.plan(for: items, now: .now, calendar: .current)
        #expect(!plan.isEmpty)

        kept.throwAway()
        #expect(ExpirationReminders.items(from: [kept, finished], meals: []).isEmpty)
    }

    @Test func suggestedDatesAreLabeledInRemindersAndRows() throws {
        let soup = Product(name: "Soup")
        context.insert(soup)
        let pot = try soup.makePackage(amount: 1, unit: .piece, purchaseDate: .now, price: nil,
                                       expirationDate: nil, storageLocation: .fridge)
        let suggestion = try #require(StorageGuidance.suggestion(for: .cooked, category: .leftovers))
        pot.changeFoodState(to: .cooked, newExpirationDate: suggestion.date(from: .now), source: .suggested)

        #expect(pot.freshnessText(now: .now) == "3 days left · suggested")
        let items = ExpirationReminders.items(from: [pot], meals: [])
        #expect(items.first?.isSuggested == true)

        let calendar = Calendar.current
        let morning = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
        let plan = ExpirationReminders.plan(for: items, now: morning, calendar: calendar)
        #expect(plan.allSatisfy { $0.title.contains("suggested") })
        // The original package date and history are kept.
        #expect(pot.originalExpirationDate == nil)
        #expect((pot.events ?? []).contains { $0.kindRaw == FoodEventKind.cooked.rawValue })
    }

    @Test func storageGuidanceOnlySuggestsWhereThereIsAClearRule() {
        #expect(StorageGuidance.suggestion(for: .cooked, category: .produce)?.days == 3)
        #expect(StorageGuidance.suggestion(for: .thawed, category: .meatSeafood)?.days == 1)
        #expect(StorageGuidance.suggestion(for: .thawed, category: .bakery) == nil)
        #expect(StorageGuidance.suggestion(for: .frozen, category: .meatSeafood) == nil)
        #expect(StorageGuidance.suggestion(for: .opened, category: .dairyEggs) == nil)
        #expect(StorageGuidance.suggestion(forPreparedMealIn: .fridge)?.days == 3)
        #expect(StorageGuidance.suggestion(forPreparedMealIn: .freezer) == nil)
        #expect(ExpirationStatus.label(daysRemaining: -1, isSuggested: true) == "Past suggested date")
        #expect(ExpirationStatus.label(daysRemaining: 0, isSuggested: true) == "Today · suggested")
    }
}
