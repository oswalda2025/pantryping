//
//  AuditRegressionTests.swift
//  Pantry PingTests
//

import Foundation
import SwiftData
import Testing
@testable import Pantry_Ping

// Regression tests for problems found in the pre-release deep audit.
@MainActor
struct AuditRegressionTests {
    let context: ModelContext

    init() throws {
        let container = try ModelContainer(for: Schema(versionedSchema: SchemaV3.self),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    private func product(_ name: String, serving: (Double, MeasureUnit)? = nil) -> Product {
        let product = Product(name: name)
        product.servingSize = serving?.0
        product.servingUnit = serving?.1
        product.nutrition = NutritionFacts(calories: 100)
        context.insert(product)
        return product
    }

    private func package(of product: Product, _ amount: Double, _ unit: MeasureUnit) throws -> GroceryItem {
        let item = try product.makePackage(amount: amount, unit: unit, purchaseDate: .now, price: nil,
                                           expirationDate: nil, storageLocation: .pantry)
        context.insert(item)
        return item
    }

    // MARK: - Rounding at the end of a package or meal

    @Test func everyOneOunceServingOfA16OunceBagCanBeUsed() throws {
        let bag = try package(of: product("Nuts", serving: (1, .ounce)), 16, .serving)
        for _ in 0..<16 {
            try bag.use(try bag.milli(for: 1, unit: .serving), reason: .ate)
        }
        #expect(bag.remainingAmountMilli == 0)
        #expect(bag.status == .used)
    }

    @Test func everyPortionOfA24PortionMealCanBeEaten() throws {
        let stew = try MealPrep.makeMeal(name: "Stew", ingredients: [], yield: .init(portions: 24, cookedWeightGrams: 1000),
                                         preparedDate: .now, storageLocation: .fridge, expirationDate: nil,
                                         expirationSource: .entered, manualBatchNutrition: nil, notes: "", in: context)
        for _ in 0..<24 {
            try stew.eat(try stew.milli(for: 1, unit: .portion))
        }
        #expect(stew.status == .used)
    }

    @Test func aPreciseAmountJustUnderWhatsLeftIsNotRoundedUp() throws {
        let bag = try package(of: product("Flour"), 1000, .gram)
        #expect(try bag.milli(for: 999, unit: .gram) == 999_000)
    }

    // MARK: - Number entry

    @Test func commasWorkAsDecimalsOrThousandsWhateverTheRegion() {
        #expect(NumberInput.double("4,5") == 4.5)
        #expect(NumberInput.double("0,25") == 0.25)
        #expect(NumberInput.double("4.5") == 4.5)
        #expect(NumberInput.double("1,000") == 1000)
        #expect(NumberInput.double("1,299.50") == 1299.5)
        #expect(NumberInput.double("") == nil)
        #expect(NumberInput.double("abc") == nil)
        #expect(NumberInput.decimal("12,50") == Decimal(string: "12.50"))
        #expect(NumberInput.decimal("$1,299.00") == Decimal(string: "1299"))
        #expect(NumberInput.decimal("4.99") == Decimal(string: "4.99"))
    }

    // MARK: - Correcting mistakes

    @Test func aMealPrepUseCanBeUndoneFromThePackage() throws {
        let rice = try package(of: product("Rice", serving: (50, .gram)), 1000, .gram)
        _ = try MealPrep.makeMeal(name: "Bowls",
                                  ingredients: [IngredientDraft(name: "Rice", package: rice, amount: 500, unit: .gram)],
                                  yield: .init(portions: 2), preparedDate: .now, storageLocation: .fridge,
                                  expirationDate: nil, expirationSource: .entered, manualBatchNutrition: nil,
                                  notes: "", in: context)
        #expect(rice.remainingAmountMilli == 500_000)
        let mealPrepUse = try #require(rice.usageEntries?.first { $0.reason == .mealPrep })
        mealPrepUse.undo(in: context)
        #expect(rice.remainingAmountMilli == 1_000_000)
    }

    @Test func deletingAPackageKeepsWhatWasEatenButRemovesItsOtherUseRecords() throws {
        let rice = try package(of: product("Rice", serving: (50, .gram)), 1000, .gram)
        try rice.use(50_000, reason: .ate)
        try rice.use(100_000, reason: .mealPrep)
        try rice.use(10_000, reason: .other)
        try context.save()

        rice.delete(in: context)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<UsageEntry>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.reason == .ate)
        #expect(remaining.first?.itemName == "Rice")
    }

    // MARK: - Food-safety wording

    @Test func pastDateAdviceNeverSaysLookAndSmellForLeftoversOrSuggestedDates() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let milk = GroceryItem(name: "Milk", expirationDate: yesterday)
        #expect(milk.pastDateGuidance == FoodState.expiredGuidance)

        let soup = GroceryItem(name: "Soup")
        soup.changeFoodState(to: .cooked, newExpirationDate: yesterday)
        #expect(soup.pastDateGuidance == FoodState.expiredLeftoverGuidance)
        #expect(!soup.pastDateGuidance.contains("smells"))

        let suggested = GroceryItem(name: "Bread")
        suggested.setUseByDate(yesterday, isCorrection: false, source: .suggested)
        #expect(suggested.pastDateGuidance == FoodState.expiredLeftoverGuidance)
    }

    @Test func foodBoughtFrozenGetsTheQualityReminderToo() {
        let peas = GroceryItem(name: "Peas", storageLocation: .freezer)
        peas.dateAdded = Calendar.current.date(byAdding: .day, value: -100, to: .now)!
        #expect(peas.freshnessText(now: .now).hasSuffix("· check quality"))
        peas.dateAdded = .now
        #expect(!peas.freshnessText(now: .now).contains("check quality"))
    }

    // MARK: - Dates

    @Test func preparedDateIsStoredAtNoonLikeOtherDates() throws {
        let meal = try MealPrep.makeMeal(name: "Stew", ingredients: [], yield: .init(portions: 2), preparedDate: .now,
                                         storageLocation: .fridge, expirationDate: nil, expirationSource: .entered,
                                         manualBatchNutrition: nil, notes: "", in: context)
        #expect(Calendar.current.component(.hour, from: meal.preparedDate) == 12)
    }
}
