//
//  MealAndMigrationTests.swift
//  Pantry PingTests
//

import Foundation
import SwiftData
import Testing
@testable import Pantry_Ping

@MainActor
struct PreparedMealTests {
    let context: ModelContext

    init() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    // Rice: 50 g servings, 180 kcal each. Chicken: 100 g servings, 165 kcal, 31 g protein.
    private func package(_ name: String, servingGrams: Double, calories: Double?, protein: Double? = nil, grams: Double) throws -> GroceryItem {
        let product = Product(name: name)
        product.servingSize = servingGrams
        product.servingUnit = .gram
        product.nutrition = NutritionFacts(calories: calories, protein: protein)
        context.insert(product)
        let item = try product.makePackage(amount: grams, unit: .gram, purchaseDate: .now, price: nil,
                                           expirationDate: nil, storageLocation: .pantry)
        context.insert(item)
        return item
    }

    private func makeMeal(_ ingredients: [IngredientDraft], portions: Double? = 4, weight: Double? = nil,
                          manual: NutritionFacts? = nil) throws -> PreparedMeal {
        try MealPrep.makeMeal(name: "Chicken Rice Bowls", ingredients: ingredients,
                              yield: .init(portions: portions, cookedWeightGrams: weight),
                              preparedDate: .now, storageLocation: .fridge, expirationDate: nil,
                              expirationSource: .entered, manualBatchNutrition: manual, notes: "", in: context)
    }

    @Test func mealPrepTakesIngredientsFromTheRightPackages() throws {
        let rice = try package("Rice", servingGrams: 50, calories: 180, grams: 1000)
        let chicken = try package("Chicken", servingGrams: 100, calories: 165, protein: 31, grams: 500)
        let otherRice = try package("Rice", servingGrams: 50, calories: 180, grams: 1000)

        let meal = try makeMeal([
            IngredientDraft(name: "Rice", package: rice, amount: 200, unit: .gram),
            IngredientDraft(name: "Chicken", package: chicken, amount: 400, unit: .gram),
        ])

        #expect(rice.remainingAmountMilli == 800_000)
        #expect(chicken.remainingAmountMilli == 100_000)
        #expect(otherRice.remainingAmountMilli == 1_000_000)
        // Meal-prep use never counts as eaten.
        #expect((rice.usageEntries ?? []).allSatisfy { $0.reason == .mealPrep })
        // 4 servings of rice (720 kcal) + 4 servings of chicken (660 kcal).
        #expect(meal.calories == 1380)
        #expect(meal.nutritionSource == .calculated)
        #expect(meal.perPortionNutrition?.calories == 345)
        // Protein is only known for chicken, so the batch total isn't claimed.
        #expect(meal.protein == nil)
    }

    @Test func overdrawingAPackageAcrossIngredientsChangesNothing() throws {
        let rice = try package("Rice", servingGrams: 50, calories: 180, grams: 300)
        #expect(throws: InventoryError.self) {
            _ = try makeMeal([
                IngredientDraft(name: "Rice", package: rice, amount: 200, unit: .gram),
                IngredientDraft(name: "Rice", package: rice, amount: 200, unit: .gram),
            ])
        }
        #expect(rice.remainingAmountMilli == 300_000)
        #expect(try context.fetch(FetchDescriptor<PreparedMeal>()).isEmpty)
    }

    @Test func untrackedIngredientMakesCaloriesIncomplete() throws {
        let rice = try package("Rice", servingGrams: 50, calories: 180, grams: 1000)
        let meal = try makeMeal([
            IngredientDraft(name: "Rice", package: rice, amount: 100, unit: .gram),
            IngredientDraft(name: "Lemon", package: nil, amount: 1, unit: .piece),
        ])
        #expect(meal.calories == nil)
        #expect(meal.ingredientsMissingCalories == 1)
    }

    @Test func eatingAPortionReducesTheMealAndLogsNutrition() throws {
        let rice = try package("Rice", servingGrams: 50, calories: 180, grams: 1000)
        let meal = try makeMeal([IngredientDraft(name: "Rice", package: rice, amount: 400, unit: .gram)],
                                portions: 4, weight: 800)
        #expect(meal.quantityUnit == .gram)
        #expect(meal.gramsPerPortion == 200)

        let entry = try meal.eat(try meal.milli(for: 1, unit: .portion))
        #expect(meal.remainingAmountMilli == 600_000)
        #expect(meal.remainingText == "3 portions · 600 g")
        #expect(entry.reason == .ate)
        #expect(entry.calories == 360)

        #expect(throws: InventoryError.self) { try meal.eat(700_000) }
    }

    @Test func manualMealWithoutMacrosIsAllowed() throws {
        let meal = try makeMeal([], portions: 3)
        #expect(meal.batchNutrition.isEmpty)
        #expect(meal.nutritionSource == .none)
        let entry = try meal.eat(1000)
        #expect(entry.nutrition.isEmpty)
        #expect(meal.remainingText == "2 portions")
    }

    @Test func manualNutritionIsUsedAsEntered() throws {
        let meal = try makeMeal([], portions: 2, manual: NutritionFacts(calories: 900))
        #expect(meal.nutritionSource == .manual)
        #expect(meal.perPortionNutrition?.calories == 450)
    }

    @Test func aMealNeedsPortionsOrAWeight() {
        #expect(throws: InventoryError.missingYield) { _ = try makeMeal([], portions: nil, weight: nil) }
    }

    @Test func finishingTheLastPortionFinishesTheMeal() throws {
        let meal = try makeMeal([], portions: 1)
        try meal.eat(1000)
        #expect(meal.status == .used)
        #expect(ExpirationReminders.items(from: [], meals: [meal]).isEmpty)
    }
}

// Regression tests for issues found in QA review.
@MainActor
struct QAFixTests {
    let context: ModelContext

    init() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    private func meal(portions: Double, grams: Double) throws -> PreparedMeal {
        try MealPrep.makeMeal(name: "Stew", ingredients: [], yield: .init(portions: portions, cookedWeightGrams: grams),
                              preparedDate: .now, storageLocation: .fridge, expirationDate: nil,
                              expirationSource: .entered, manualBatchNutrition: nil, notes: "", in: context)
    }

    @Test func threeThirdsFinishAMealExactly() throws {
        let stew = try meal(portions: 3, grams: 1000)
        for _ in 0..<3 {
            try stew.eat(try stew.milli(for: 1, unit: .portion))
        }
        #expect(stew.remainingAmountMilli == 0)
        #expect(stew.status == .used)
    }

    @Test func theLastOfSixPortionsIsAccepted() throws {
        let stew = try meal(portions: 6, grams: 1000)
        for _ in 0..<6 {
            try stew.eat(try stew.milli(for: 1, unit: .portion))
        }
        #expect(stew.status == .used)
    }

    @Test func absurdAmountsAreRejectedInsteadOfCrashing() throws {
        let product = Product(name: "Flour")
        context.insert(product)
        let bag = try product.makePackage(amount: 1000, unit: .gram, purchaseDate: .now, price: nil,
                                          expirationDate: nil, storageLocation: .pantry)
        #expect(throws: InventoryError.invalidAmount) { try bag.milli(for: 1e20, unit: .gram) }
        #expect(throws: InventoryError.self) {
            _ = try product.makePackage(amount: 1e30, unit: .gram, purchaseDate: .now, price: nil,
                                        expirationDate: nil, storageLocation: .pantry)
        }
        #expect(throws: InventoryError.self) { _ = try meal(portions: 1e30, grams: 0) }
    }

    @Test func correctingAfterStillHaveItKeepsTheOriginalPackageDate() {
        let day = { (offset: Int) in Calendar.current.date(byAdding: .day, value: offset, to: .now)! }
        let milk = GroceryItem(name: "Milk", expirationDate: day(-2))
        let original = milk.originalExpirationDate
        milk.setUseByDate(day(3), isCorrection: false)   // "Still have it"
        milk.setUseByDate(day(5), isCorrection: true)    // later edit in the form
        #expect(milk.originalExpirationDate == original)
    }

    @Test func anEmptiedPackageCantBeMovedBack() throws {
        let product = Product(name: "Juice")
        context.insert(product)
        let carton = try product.makePackage(amount: 1, unit: .liter, purchaseDate: .now, price: nil,
                                             expirationDate: nil, storageLocation: .fridge)
        try carton.use(carton.remainingAmountMilli, reason: .ate)
        #expect(carton.status == .used)
        #expect(!carton.canRestoreToKitchen)
        carton.restoreToKitchen()
        #expect(carton.status == .used)
    }

    @Test func mealPrepRefusesAFinishedPackageBeforeChangingAnything() throws {
        let product = Product(name: "Rice")
        context.insert(product)
        let bag = try product.makePackage(amount: 500, unit: .gram, purchaseDate: .now, price: nil,
                                          expirationDate: nil, storageLocation: .pantry)
        context.insert(bag)
        bag.finish()
        #expect(throws: InventoryError.notActive) {
            _ = try MealPrep.makeMeal(name: "Bowl", ingredients: [IngredientDraft(name: "Rice", package: bag, amount: 100, unit: .gram)],
                                      yield: .init(portions: 2), preparedDate: .now, storageLocation: .fridge,
                                      expirationDate: nil, expirationSource: .entered, manualBatchNutrition: nil,
                                      notes: "", in: context)
        }
        #expect(bag.remainingAmountMilli == 500_000)
        #expect(try context.fetch(FetchDescriptor<PreparedMeal>()).isEmpty)
    }
}

// Opens a real on-disk V1 database with the V2 app, as an app update would.
@MainActor
struct MigrationTests {
    @Test func v1DataUpgradesToPackagesWithProducts() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "migration-test.store")
        defer { try? FileManager.default.removeItem(at: folder) }

        // 1. Write V1 data and close the database.
        do {
            let v1 = try ModelContainer(for: Schema(versionedSchema: SchemaV1.self),
                                        configurations: ModelConfiguration(url: url))
            let context = ModelContext(v1)
            let eggs = SchemaV1.GroceryItem(name: "Eggs")
            eggs.quantity = 12
            let milk = SchemaV1.GroceryItem(name: "Milk")
            milk.expirationDate = .now
            let moreMilk = SchemaV1.GroceryItem(name: "milk")
            moreMilk.statusRaw = "used"
            [eggs, milk, moreMilk].forEach(context.insert)
            try context.save()
        }

        // 2. Open it with the current schema and migration plan.
        let v2 = try ModelContainer(for: Schema(versionedSchema: SchemaV2.self),
                                    migrationPlan: PantryPingMigrationPlan.self,
                                    configurations: ModelConfiguration(url: url))
        let context = ModelContext(v2)
        let items = try context.fetch(FetchDescriptor<GroceryItem>())
        let products = try context.fetch(FetchDescriptor<Product>())

        #expect(items.count == 3)
        // "Milk" and "milk" share one saved product.
        #expect(products.count == 2)
        let eggs = try #require(items.first { $0.name == "Eggs" })
        #expect(eggs.quantityUnit == .piece)
        #expect(eggs.remainingAmountMilli == 12_000)
        #expect(eggs.product?.name == "Eggs")
        #expect((eggs.events ?? []).contains { $0.kindRaw == FoodEventKind.purchased.rawValue })
        // Existing dates and statuses are untouched.
        #expect(items.first { $0.name == "Milk" }?.expirationDate != nil)
        #expect(items.first { $0.name == "milk" }?.status == .used)
    }
}

// If the saved database can't be opened, the app starts fresh instead of crashing on
// every launch, and keeps the unreadable file as a backup.
@MainActor
struct DatabaseRecoveryTests {
    @Test func unreadableDatabaseIsMovedAsideNotDeleted() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
            UserDefaults.standard.removeObject(forKey: DatabaseLoader.recoveryNoteKey)
        }
        let url = folder.appending(path: "broken.store")
        try Data("this is not a database".utf8).write(to: url)

        let container = DatabaseLoader.openOrRecover(schema: Schema(versionedSchema: SchemaV2.self),
                                                     configuration: ModelConfiguration(url: url))
        // The fresh database works.
        let context = ModelContext(container)
        context.insert(Product(name: "Test"))
        try context.save()

        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.contains { $0.hasPrefix("broken.store-unreadable-") })
        #expect(UserDefaults.standard.string(forKey: DatabaseLoader.recoveryNoteKey)?.contains("backup") == true)
    }
}
