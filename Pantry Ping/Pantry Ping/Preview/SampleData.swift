//
//  SampleData.swift
//  Pantry Ping
//

import Foundation
import SwiftData

// Demo data covering every urgency level, food states, a part-used package with nutrition,
// a prepared meal, and a shopping list. Used by SwiftUI previews and the
// "Try Sample Groceries" button, so the app can be explored without typing.
enum SampleData {
    // A throwaway in-memory database for #Preview canvases. `isStoredInMemoryOnly`
    // means nothing is written to disk.
    static let previewContainer: ModelContainer = {
        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: SchemaV2.self),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            insertSampleGroceries(into: container.mainContext)
            return container
        } catch {
            fatalError("Could not create preview container: \(error)")
        }
    }()

    // One item from the preview database, for previews of single-item screens.
    static var previewSampleItem: GroceryItem {
        let items = (try? previewContainer.mainContext.fetch(FetchDescriptor<GroceryItem>())) ?? []
        return items.first { $0.name == "Milk" } ?? GroceryItem(name: "Milk")
    }

    static func insertSampleGroceries(into context: ModelContext, now: Date = .now) {
        let calendar = Calendar.current
        // A small helper: a date `offset` days from today.
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: now) ?? now
        }

        // Reuse saved products with the same name, so loading samples twice doesn't
        // duplicate the catalog.
        let existing = (try? context.fetch(FetchDescriptor<Product>())) ?? []
        func product(_ name: String, _ category: GroceryCategory, serving: (Double, MeasureUnit)? = nil,
                     servingsPerPackage: Double? = nil, nutrition: NutritionFacts = .empty) -> Product {
            if let match = existing.first(where: { $0.name == name }) { return match }
            let product = Product(name: name, category: category)
            product.servingSize = serving?.0
            product.servingUnit = serving?.1
            product.servingsPerPackage = servingsPerPackage
            product.nutrition = nutrition
            context.insert(product)
            return product
        }

        // `@discardableResult` means callers may ignore the returned package.
        @discardableResult
        func buy(_ product: Product, _ amount: Double = 1, _ unit: MeasureUnit = .piece,
                 in location: StorageLocation = .fridge, bought: Int, expires: Int?) -> GroceryItem? {
            guard let package = try? product.makePackage(
                amount: amount, unit: unit, purchaseDate: day(bought), price: nil,
                expirationDate: expires.map(day), storageLocation: location
            ) else { return nil }
            context.insert(package)
            return package
        }

        buy(product("Strawberries", .produce), bought: -5, expires: -1)
        buy(product("Spinach", .produce), bought: -4, expires: 0)
        buy(product("Milk", .dairyEggs), bought: -6, expires: 1)
        buy(product("Sourdough Bread", .bakery), in: .pantry, bought: -2, expires: 2)
        buy(product("Greek Yogurt", .dairyEggs, serving: (170, .gram), servingsPerPackage: 1,
                    nutrition: NutritionFacts(calories: 100, carbs: 6, protein: 17, fat: 0.7)),
            1, .serving, bought: -3, expires: 3)
        buy(product("Bell Peppers", .produce), 3, bought: -1, expires: 6)
        buy(product("Eggs", .dairyEggs), 12, bought: -2, expires: 18)

        let rice = product("Rice", .dryCanned, serving: (45, .gram),
                           nutrition: NutritionFacts(calories: 160, carbs: 36, protein: 3, fat: 0))
        let ricePackage = buy(rice, 1000, .gram, in: .pantry, bought: -20, expires: nil)

        // The granola example: 5 × 62 g servings, with 31 g already eaten today.
        let granola = product("Quaker Protein Granola", .dryCanned, serving: (62, .gram), servingsPerPackage: 5,
                              nutrition: NutritionFacts(calories: 260, carbs: 44, protein: 10, fat: 7))
        if let box = buy(granola, 5, .serving, in: .pantry, bought: -3, expires: 60) {
            _ = try? box.use(31_000, reason: .ate, on: now)
        }

        if let chicken = buy(product("Chicken Breast", .meatSeafood), 500, .gram, bought: -5, expires: -3) {
            chicken.changeFoodState(to: .frozen, newExpirationDate: nil, on: day(-4))
        }
        if let pasta = buy(product("Pasta Bake", .leftovers), bought: -1, expires: nil) {
            pasta.changeFoodState(to: .cooked, newExpirationDate: day(2), on: day(-1))
        }

        // A meal-prep batch made yesterday from the rice, with the fridge suggestion applied.
        if let ricePackage {
            let suggested = StorageGuidance.suggestion(forPreparedMealIn: .fridge)?.date(from: day(-1))
            if let meal = try? MealPrep.makeMeal(
                name: "Chicken Rice Bowls",
                ingredients: [
                    IngredientDraft(name: "Rice", package: ricePackage, amount: 180, unit: .gram),
                    IngredientDraft(name: "Lemon", package: nil, amount: 1, unit: .piece),
                ],
                yield: .init(portions: 4, cookedWeightGrams: nil),
                preparedDate: day(-1),
                storageLocation: .fridge,
                expirationDate: suggested,
                expirationSource: .suggested,
                manualBatchNutrition: NutritionFacts(calories: 2200, carbs: 240, protein: 160, fat: 50),
                notes: "",
                in: context
            ) {
                _ = try? meal.eat(1000, on: day(-1))
            }
        }

        context.insert(ShoppingItem(name: "Bananas"))
        ShoppingList.add(granola, in: context)
    }
}
