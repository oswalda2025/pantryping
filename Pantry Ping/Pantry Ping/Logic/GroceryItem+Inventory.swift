//
//  GroceryItem+Inventory.swift
//  Pantry Ping
//

import Foundation
import SwiftData

// Errors an inventory action can report. `LocalizedError` gives each one a message
// the UI can show directly.
enum InventoryError: LocalizedError, Equatable {
    case invalidAmount
    case notEnoughLeft(available: String)
    case noConversion(from: MeasureUnit)
    case notActive
    case missingYield

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            "Enter an amount greater than zero."
        case .notEnoughLeft(let available):
            "That's more than what's left (\(available))."
        case .noConversion(let unit):
            "Pantry Ping doesn't know how many \(unit.label(for: 2)) this is. Add a serving size to the product, or use a different unit."
        case .notActive:
            "This item is no longer in your kitchen."
        case .missingYield:
            "Enter the number of portions or the cooked weight."
        }
    }
}

extension GroceryItem {
    var converter: QuantityConverter {
        QuantityConverter(baseUnit: quantityUnit, servingSize: product?.servingSize, servingUnit: product?.servingUnit)
    }

    var remainingAmount: Double { Quantity.value(remainingAmountMilli) }

    var remainingServings: Double? {
        converter.servings(fromBase: remainingAmount)
    }

    // "279 g · 4.5 servings"
    func amountText(milli: Int) -> String {
        converter.text(forBase: Quantity.value(milli))
    }

    var remainingText: String { amountText(milli: remainingAmountMilli) }
    var startingText: String { amountText(milli: startingAmountMilli) }

    // A plain "1 piece" that was never used isn't worth showing on a row.
    var hasMeaningfulAmount: Bool {
        !(quantityUnit == .piece && startingAmountMilli == 1000 && remainingAmountMilli == 1000)
    }

    // Converts a typed amount (e.g. 31 g or 0.5 servings) into this package's milli-units.
    func milli(for value: Double, unit: MeasureUnit) throws -> Int {
        guard value > 0, value.isFinite else { throw InventoryError.invalidAmount }
        guard let base = converter.toBase(value, from: unit) else {
            throw InventoryError.noConversion(from: unit)
        }
        let milli = Quantity.snapped(Quantity.milli(base), toRemaining: remainingAmountMilli)
        guard milli > 0 else { throw InventoryError.invalidAmount }
        return milli
    }

    // Nutrition for an amount of this package, scaled from the product's per-serving values.
    // Empty when the product has no nutrition or the amount can't be expressed in servings.
    func nutrition(forMilli milli: Int) -> NutritionFacts {
        guard let product, let servings = converter.servings(fromBase: Quantity.value(milli)) else {
            return .empty
        }
        return product.nutrition.scaled(by: servings)
    }

    // MARK: - Actions

    // Takes an amount out of this package and records why. It refuses to take more than
    // what's left, so inventory can never go negative. Emptying the package finishes it.
    @discardableResult
    func use(_ milli: Int, reason: UsageReason, on date: Date = .now) throws -> UsageEntry {
        guard status == .active else { throw InventoryError.notActive }
        guard milli > 0 else { throw InventoryError.invalidAmount }
        guard milli <= remainingAmountMilli else {
            throw InventoryError.notEnoughLeft(available: remainingText)
        }
        remainingAmountMilli -= milli

        let entry = UsageEntry(
            date: date,
            reason: reason,
            amountMilli: milli,
            unit: quantityUnit,
            itemName: displayName,
            nutrition: nutrition(forMilli: milli)
        )
        entry.package = self

        if remainingAmountMilli == 0 {
            finish(on: date, detail: "All used up")
        }
        return entry
    }

    // Finished or thrown away items leave the kitchen (and stop reminders) but keep their history.
    func finish(on date: Date = .now, detail: String = "") {
        status = .used
        addEvent(.finished, date: date, detail: detail)
    }

    func throwAway(on date: Date = .now) {
        status = .discarded
        addEvent(.discarded, date: date, detail: remainingAmountMilli > 0 ? "\(remainingText) left" : "")
    }

    // An emptied package has nothing to move back, so it can't be restored.
    var canRestoreToKitchen: Bool {
        status != .active && remainingAmountMilli > 0
    }

    func restoreToKitchen(on date: Date = .now) {
        guard remainingAmountMilli > 0 else { return }
        status = .active
        addEvent(.restored, date: date)
    }

    // Permanently deletes this package. What was eaten stays in the Food Log; its other
    // use records (meal prep, other) belong only to this package, so they go with it.
    func delete(in context: ModelContext) {
        for entry in usageEntries ?? [] where entry.reason != .ate {
            context.delete(entry)
        }
        context.delete(self)
    }

    // Moves the package somewhere else and records it, e.g. from the edit form.
    func move(to location: StorageLocation, on date: Date = .now) {
        guard location != storageLocation else { return }
        addEvent(.moved, date: date, detail: "\(storageLocation.displayName) → \(location.displayName)")
        storageLocation = location
    }
}

extension UsageEntry {
    var reason: UsageReason { UsageReason(rawValue: reasonRaw) ?? .other }
    var unit: MeasureUnit { MeasureUnit(rawValue: unitRaw) ?? .serving }

    var nutrition: NutritionFacts {
        NutritionFacts(calories: calories, carbs: carbs, protein: protein, fat: fat)
    }

    // "31 g · 0.5 servings", using the source's conversions when it still exists.
    var amountText: String {
        let value = Quantity.value(amountMilli)
        if let package, package.quantityUnit == unit {
            return package.converter.text(forBase: value)
        }
        if let preparedMeal, preparedMeal.quantityUnit == unit {
            return preparedMeal.amountText(milli: amountMilli)
        }
        return Quantity.text(value, unit: unit)
    }

    // Deletes this entry and puts the amount back where it came from. If taking it had
    // emptied (and so finished) the source, the source comes back to the kitchen.
    func undo(in context: ModelContext) {
        if let package, package.quantityUnit == unit {
            let wasEmpty = package.remainingAmountMilli == 0
            package.remainingAmountMilli = min(package.startingAmountMilli, package.remainingAmountMilli + amountMilli)
            if wasEmpty && package.status == .used {
                package.restoreToKitchen()
            }
        }
        if let meal = preparedMeal, meal.quantityUnit == unit {
            let wasEmpty = meal.remainingAmountMilli == 0
            meal.remainingAmountMilli = min(meal.startingAmountMilli, meal.remainingAmountMilli + amountMilli)
            if wasEmpty && meal.status == .used {
                meal.status = .active
            }
        }
        context.delete(self)
    }
}
