//
//  PreparedMeal+Logic.swift
//  Pantry Ping
//

import Foundation
import SwiftData

// Where a meal's nutrition came from.
enum NutritionSource: String {
    case calculated, manual, none
}

extension PreparedMeal {
    var storageLocation: StorageLocation {
        get { StorageLocation(rawValue: storageLocationRaw) ?? .fridge }
        set { storageLocationRaw = newValue.rawValue }
    }

    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .active }
        set {
            statusRaw = newValue.rawValue
            dateResolved = newValue == .active ? nil : .now
        }
    }

    var expirationSource: ExpirationSource {
        get { ExpirationSource(rawValue: expirationSourceRaw) ?? .entered }
        set { expirationSourceRaw = newValue.rawValue }
    }

    var quantityUnit: MeasureUnit { MeasureUnit(rawValue: quantityUnitRaw) ?? .portion }

    var nutritionSource: NutritionSource { NutritionSource(rawValue: nutritionSourceRaw) ?? .none }

    // Nutrition for the whole batch (values may be nil = unknown).
    var batchNutrition: NutritionFacts {
        get { NutritionFacts(calories: calories, carbs: carbs, protein: protein, fat: fat) }
        set {
            calories = newValue.calories
            carbs = newValue.carbs
            protein = newValue.protein
            fat = newValue.fat
        }
    }

    // Known only when both the portion count and the cooked weight were entered.
    var gramsPerPortion: Double? {
        guard let totalWeightGrams, let totalPortions, totalWeightGrams > 0, totalPortions > 0 else { return nil }
        return totalWeightGrams / totalPortions
    }

    var perPortionNutrition: NutritionFacts? {
        guard let totalPortions, totalPortions > 0, !batchNutrition.isEmpty else { return nil }
        return batchNutrition.scaled(by: 1 / totalPortions)
    }

    var per100gNutrition: NutritionFacts? {
        guard let totalWeightGrams, totalWeightGrams > 0, !batchNutrition.isEmpty else { return nil }
        return batchNutrition.scaled(by: 100 / totalWeightGrams)
    }

    // A converter that treats one portion like a "serving" of the cooked weight.
    var converter: QuantityConverter {
        if quantityUnit == .gram {
            return QuantityConverter(baseUnit: .gram, servingSize: gramsPerPortion, servingUnit: .gram)
        }
        return QuantityConverter(baseUnit: .portion, servingSize: nil, servingUnit: nil)
    }

    // Units that can be logged: portions and/or grams, depending on what's known.
    var enterableUnits: [MeasureUnit] {
        switch quantityUnit {
        case .gram: gramsPerPortion != nil ? [.portion, .gram, .ounce] : [.gram, .ounce]
        default: [.portion]
        }
    }

    // Base-unit value for a typed amount, treating "portion" as a serving of the batch.
    func milli(for value: Double, unit: MeasureUnit) throws -> Int {
        guard value > 0, value.isFinite else { throw InventoryError.invalidAmount }
        let base: Double?
        if unit == quantityUnit {
            base = value
        } else if unit == .portion {
            base = gramsPerPortion.map { value * $0 }
        } else {
            base = converter.toBase(value, from: unit)
        }
        guard let base else { throw InventoryError.noConversion(from: unit) }
        let milli = Quantity.snapped(Quantity.milli(base), toRemaining: remainingAmountMilli)
        guard milli > 0 else { throw InventoryError.invalidAmount }
        return milli
    }

    var canRestoreToKitchen: Bool {
        status != .active && remainingAmountMilli > 0
    }

    // "3 portions · 450 g" when both are known.
    func amountText(milli: Int) -> String {
        let value = Quantity.value(milli)
        if quantityUnit == .gram {
            let grams = Quantity.text(value, unit: .gram)
            guard let perPortion = gramsPerPortion else { return grams }
            return "\(Quantity.text(value / perPortion, unit: .portion)) · \(grams)"
        }
        return Quantity.text(value, unit: .portion)
    }

    var remainingText: String { amountText(milli: remainingAmountMilli) }

    // Nutrition for part of the batch, as a share of the starting amount.
    func nutrition(forMilli milli: Int) -> NutritionFacts {
        guard startingAmountMilli > 0 else { return .empty }
        return batchNutrition.scaled(by: Double(milli) / Double(startingAmountMilli))
    }

    // Logs eating some of the meal. Counts toward the daily food log.
    @discardableResult
    func eat(_ milli: Int, on date: Date = .now) throws -> UsageEntry {
        guard status == .active else { throw InventoryError.notActive }
        guard milli > 0 else { throw InventoryError.invalidAmount }
        guard milli <= remainingAmountMilli else {
            throw InventoryError.notEnoughLeft(available: remainingText)
        }
        remainingAmountMilli -= milli
        let entry = UsageEntry(
            date: date,
            reason: .ate,
            amountMilli: milli,
            unit: quantityUnit,
            itemName: name,
            nutrition: nutrition(forMilli: milli)
        )
        entry.preparedMeal = self
        if remainingAmountMilli == 0 {
            status = .used
        }
        return entry
    }

    // Counts of ingredients that do and don't have calories, for the "incomplete" note.
    var ingredientsMissingCalories: Int {
        (ingredients ?? []).filter { $0.calories == nil }.count
    }

    // MARK: - Freshness (same rules as groceries)

    func daysRemaining(now: Date, calendar: Calendar = .current) -> Int? {
        ExpirationStatus.daysRemaining(until: expirationDate, now: now, calendar: calendar)
    }

    func expirationStatus(now: Date) -> ExpirationStatus {
        ExpirationStatus(daysRemaining: daysRemaining(now: now))
    }

    func freshnessText(now: Date) -> String {
        if let days = daysRemaining(now: now) {
            return ExpirationStatus.label(daysRemaining: days, isSuggested: expirationSource == .suggested)
        }
        return "Made \(GroceryItem.relativeDayText(from: preparedDate, now: now))"
    }
}

extension MealIngredient {
    var unit: MeasureUnit { MeasureUnit(rawValue: unitRaw) ?? .serving }
    var nutrition: NutritionFacts { NutritionFacts(calories: calories, carbs: carbs, protein: protein, fat: fat) }
    var amountText: String { Quantity.text(Quantity.value(amountMilli), unit: unit) }
}

// One ingredient being added in the meal-prep form, before anything is saved.
// A struct is a value type: copying it copies the data, which suits form state.
struct IngredientDraft: Identifiable {
    let id = UUID()
    var name: String
    // The inventory package it comes from, or nil for something not tracked.
    var package: GroceryItem?
    var amount: Double
    var unit: MeasureUnit
}

// Creating a prepared meal touches several packages at once, so it lives in one place.
enum MealPrep {
    struct Yield {
        var portions: Double?
        var cookedWeightGrams: Double?
    }

    // Checks every ingredient amount FIRST, then takes them out of their packages, so a
    // problem part-way never leaves the inventory half-updated.
    static func makeMeal(
        name: String,
        ingredients: [IngredientDraft],
        yield: Yield,
        preparedDate: Date,
        storageLocation: StorageLocation,
        expirationDate: Date?,
        expirationSource: ExpirationSource,
        manualBatchNutrition: NutritionFacts?,
        notes: String,
        in context: ModelContext
    ) throws -> PreparedMeal {
        let portions = yield.portions.flatMap { $0 > 0 ? $0 : nil }
        let weight = yield.cookedWeightGrams.flatMap { $0 > 0 ? $0 : nil }
        guard portions != nil || weight != nil else { throw InventoryError.missingYield }

        // 1. Validate: convert each amount and make sure no package is over-drawn,
        //    even when two ingredients come from the same package.
        var milliByDraft: [UUID: Int] = [:]
        var totalByPackage: [PersistentIdentifier: Int] = [:]
        for draft in ingredients {
            guard let package = draft.package else {
                guard draft.amount > 0, Quantity.milli(draft.amount) > 0 else { throw InventoryError.invalidAmount }
                continue
            }
            guard package.status == .active else { throw InventoryError.notActive }
            let milli = try package.milli(for: draft.amount, unit: draft.unit)
            milliByDraft[draft.id] = milli
            totalByPackage[package.persistentModelID, default: 0] += milli
            if totalByPackage[package.persistentModelID, default: 0] > package.remainingAmountMilli {
                throw InventoryError.notEnoughLeft(available: "\(package.displayName): \(package.remainingText)")
            }
        }

        // 2. Create the meal.
        let meal = PreparedMeal(name: name, preparedDate: preparedDate, storageLocation: storageLocation)
        meal.totalPortions = portions
        meal.totalWeightGrams = weight
        meal.quantityUnitRaw = (weight != nil ? MeasureUnit.gram : MeasureUnit.portion).rawValue
        let starting = Quantity.milli(weight ?? portions ?? 1)
        guard starting > 0 else { throw InventoryError.invalidAmount }
        meal.startingAmountMilli = starting
        meal.remainingAmountMilli = starting
        meal.expirationDate = expirationDate.map { CalendarDay.noon($0) }
        meal.expirationSource = expirationDate == nil ? .entered : expirationSource
        meal.notes = notes

        // 3. Take ingredients out of inventory and record them on the meal.
        var total = NutritionTotal()
        for draft in ingredients {
            let ingredient: MealIngredient
            if let package = draft.package, let milli = milliByDraft[draft.id] {
                let entry = try package.use(milli, reason: .mealPrep, on: preparedDate)
                ingredient = MealIngredient(name: package.displayName, amountMilli: milli, unit: package.quantityUnit,
                                            fromInventory: true, nutrition: entry.nutrition)
            } else {
                // Not tracked in the kitchen: recorded as typed, with no nutrition.
                ingredient = MealIngredient(name: draft.name, amountMilli: Quantity.milli(draft.amount), unit: draft.unit,
                                            fromInventory: false, nutrition: .empty)
            }
            ingredient.meal = meal
            total.add(ingredient.nutrition)
        }

        // Inserted last, so nothing half-built is ever saved.
        context.insert(meal)

        // 4. Nutrition: typed-in values win; otherwise add up ingredients, keeping only
        //    values every ingredient had (an incomplete sum is never shown as exact).
        if let manual = manualBatchNutrition, !manual.isEmpty {
            meal.batchNutrition = manual
            meal.nutritionSourceRaw = NutritionSource.manual.rawValue
        } else if !ingredients.isEmpty, !total.completeFacts.isEmpty {
            meal.batchNutrition = total.completeFacts
            meal.nutritionSourceRaw = NutritionSource.calculated.rawValue
        }
        return meal
    }
}
