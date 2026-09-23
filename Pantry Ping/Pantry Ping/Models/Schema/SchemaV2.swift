//
//  SchemaV2.swift
//  Pantry Ping
//

import Foundation
import SwiftData

// Version 2 of the database. It separates four ideas that V1 lumped together:
//   Product      — reusable details for a food (name, serving size, nutrition, photo)
//   GroceryItem  — one purchased package or batch of a product (dates, price, amount left)
//   UsageEntry   — an amount taken from a package or prepared meal, with a reason
//   PreparedMeal — a batch cooked from ingredients, with its own portions
// plus ShoppingItem (the shopping list) and FoodEvent (a package's dated history).
//
// Rules that keep the database safe to evolve:
// - Every stored property has a default in its declaration.
// - Enums are stored as raw Strings whose values never change.
// - Relationships are optional arrays, so iCloud sync stays possible later.
// - Quantities are whole numbers of thousandths ("milli-units") of a base unit,
//   so repeated partial uses never pile up floating-point rounding errors.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [GroceryItem.self, Product.self, UsageEntry.self, FoodEvent.self,
         PreparedMeal.self, MealIngredient.self, ShoppingItem.self]
    }

    // MARK: - Product

    @Model
    final class Product {
        var id: UUID = UUID()
        var name: String = ""
        var categoryRaw: String = "other"

        // One serving, as printed on the label: e.g. 62 g, 1 cup, 2 tbsp, 1 piece.
        // Both are optional: many foods are tracked without any serving information.
        var servingSize: Double? = nil
        var servingUnitRaw: String? = nil
        // The usual number of servings in one package, used as the default when buying.
        var servingsPerPackage: Double? = nil

        // Nutrition per ONE serving. nil means "not entered" — never treated as zero.
        var calories: Double? = nil
        var carbs: Double? = nil
        var protein: Double? = nil
        var fat: Double? = nil

        // `.externalStorage` lets SwiftData keep large data (like photos) in a separate
        // file instead of inside the database row, which keeps the database fast.
        @Attribute(.externalStorage) var photoData: Data? = nil

        var dateCreated: Date = Date()

        // Deleting a product never deletes its packages or shopping-list entries (.nullify).
        @Relationship(deleteRule: .nullify, inverse: \GroceryItem.product)
        var packages: [GroceryItem]? = []
        @Relationship(deleteRule: .nullify, inverse: \ShoppingItem.product)
        var shoppingItems: [ShoppingItem]? = []

        init(name: String, category: GroceryCategory = .other) {
            self.name = name
            self.categoryRaw = category.rawValue
        }
    }

    // MARK: - GroceryItem (a purchased package)

    @Model
    final class GroceryItem {
        // --- Fields from V1 (unchanged) ---
        var id: UUID = UUID()
        var name: String = ""
        var categoryRaw: String = "other"
        var storageLocationRaw: String = "fridge"
        var statusRaw: String = "active"
        // Legacy V1 whole-number count. The migration copies it into the amounts below.
        var quantity: Double = 1
        var purchaseDate: Date = Date()
        // The CURRENT use-by date the countdown and reminders use.
        var expirationDate: Date? = nil
        // The date entered when the package was bought. State changes never touch it.
        var originalExpirationDate: Date? = nil
        var foodStateRaw: String = "fresh"
        var dateOpened: Date? = nil
        var dateCooked: Date? = nil
        var dateFrozen: Date? = nil
        var dateThawed: Date? = nil
        var notes: String = ""
        var dateAdded: Date = Date()
        var dateResolved: Date? = nil

        // --- New in V2 ---
        var product: Product?
        // `Decimal` stores money exactly (a Double can't represent 0.10 precisely).
        var price: Decimal? = nil
        // Whether `expirationDate` was typed by the user or taken from general guidance.
        var expirationSourceRaw: String = "entered"
        // Amounts in thousandths of `quantityUnitRaw` (g, ml, piece, or serving).
        var quantityUnitRaw: String = "piece"
        var startingAmountMilli: Int = 1000
        var remainingAmountMilli: Int = 1000

        // Usage entries survive if the package is deleted, so the food log stays intact.
        @Relationship(deleteRule: .nullify, inverse: \UsageEntry.package)
        var usageEntries: [UsageEntry]? = []
        @Relationship(deleteRule: .cascade, inverse: \FoodEvent.package)
        var events: [FoodEvent]? = []

        init(
            name: String,
            category: GroceryCategory = .other,
            storageLocation: StorageLocation = .fridge,
            quantity: Double = 1,
            purchaseDate: Date = .now,
            expirationDate: Date? = nil,
            notes: String = ""
        ) {
            self.name = name
            self.categoryRaw = category.rawValue
            self.storageLocationRaw = storageLocation.rawValue
            self.quantity = quantity
            self.quantityUnitRaw = MeasureUnit.piece.rawValue
            self.startingAmountMilli = Quantity.milli(quantity)
            self.remainingAmountMilli = Quantity.milli(quantity)
            self.purchaseDate = CalendarDay.noon(purchaseDate)
            // `.map` runs only when the optional holds a value; nil stays nil.
            let day = expirationDate.map { CalendarDay.noon($0) }
            self.expirationDate = day
            self.originalExpirationDate = day
            self.notes = notes
            self.dateAdded = .now
        }
    }

    // MARK: - UsageEntry

    @Model
    final class UsageEntry {
        var id: UUID = UUID()
        var date: Date = Date()
        var reasonRaw: String = "ate"
        // The amount taken, in thousandths of `unitRaw` (the source's base unit at the time).
        var amountMilli: Int = 0
        var unitRaw: String = "serving"
        // A copy of the name, so the log still reads correctly if the source is deleted.
        var itemName: String = ""
        // Nutrition for exactly this amount, worked out when logged. nil = not entered.
        var calories: Double? = nil
        var carbs: Double? = nil
        var protein: Double? = nil
        var fat: Double? = nil
        // Exactly one of these is set: where the food came from.
        var package: GroceryItem?
        var preparedMeal: PreparedMeal?

        init(date: Date, reason: UsageReason, amountMilli: Int, unit: MeasureUnit, itemName: String, nutrition: NutritionFacts) {
            self.date = date
            self.reasonRaw = reason.rawValue
            self.amountMilli = amountMilli
            self.unitRaw = unit.rawValue
            self.itemName = itemName
            self.calories = nutrition.calories
            self.carbs = nutrition.carbs
            self.protein = nutrition.protein
            self.fat = nutrition.fat
        }
    }

    // MARK: - FoodEvent (a dated line in a package's or meal's history)

    @Model
    final class FoodEvent {
        var date: Date = Date()
        var kindRaw: String = "note"
        var detail: String = ""
        var package: GroceryItem?
        var preparedMeal: PreparedMeal?

        init(kind: FoodEventKind, date: Date = .now, detail: String = "") {
            self.kindRaw = kind.rawValue
            self.date = date
            self.detail = detail
        }
    }

    // MARK: - PreparedMeal

    @Model
    final class PreparedMeal {
        var id: UUID = UUID()
        var name: String = ""
        var preparedDate: Date = Date()
        var storageLocationRaw: String = "fridge"
        var expirationDate: Date? = nil
        var expirationSourceRaw: String = "entered"
        var statusRaw: String = "active"
        var dateResolved: Date? = nil
        var notes: String = ""

        // The yield: a number of portions, a cooked weight, or both.
        var totalPortions: Double? = nil
        var totalWeightGrams: Double? = nil
        // Grams when a weight was entered, otherwise portions.
        var quantityUnitRaw: String = "portion"
        var startingAmountMilli: Int = 1000
        var remainingAmountMilli: Int = 1000

        // Nutrition for the WHOLE batch. nil = unknown (not entered or incomplete).
        var calories: Double? = nil
        var carbs: Double? = nil
        var protein: Double? = nil
        var fat: Double? = nil
        // "calculated" from ingredients, "manual", or "none".
        var nutritionSourceRaw: String = "none"

        @Relationship(deleteRule: .cascade, inverse: \MealIngredient.meal)
        var ingredients: [MealIngredient]? = []
        @Relationship(deleteRule: .nullify, inverse: \UsageEntry.preparedMeal)
        var usageEntries: [UsageEntry]? = []
        @Relationship(deleteRule: .cascade, inverse: \FoodEvent.preparedMeal)
        var events: [FoodEvent]? = []

        init(name: String, preparedDate: Date = .now, storageLocation: StorageLocation = .fridge) {
            self.name = name
            self.preparedDate = preparedDate
            self.storageLocationRaw = storageLocation.rawValue
        }
    }

    // MARK: - MealIngredient

    @Model
    final class MealIngredient {
        var name: String = ""
        var amountMilli: Int = 0
        var unitRaw: String = "serving"
        // True when the amount was taken out of a package in the inventory.
        var fromInventory: Bool = false
        // Nutrition for this amount. nil = not entered.
        var calories: Double? = nil
        var carbs: Double? = nil
        var protein: Double? = nil
        var fat: Double? = nil
        var meal: PreparedMeal?

        init(name: String, amountMilli: Int, unit: MeasureUnit, fromInventory: Bool, nutrition: NutritionFacts) {
            self.name = name
            self.amountMilli = amountMilli
            self.unitRaw = unit.rawValue
            self.fromInventory = fromInventory
            self.calories = nutrition.calories
            self.carbs = nutrition.carbs
            self.protein = nutrition.protein
            self.fat = nutrition.fat
        }
    }

    // MARK: - ShoppingItem

    @Model
    final class ShoppingItem {
        var id: UUID = UUID()
        var name: String = ""
        var note: String = ""
        var dateAdded: Date = Date()
        // Set when the entry came from a saved product, so buying it can reuse its details.
        var product: Product?

        init(name: String, note: String = "", product: Product? = nil) {
            self.name = name
            self.note = note
            self.product = product
        }
    }
}
