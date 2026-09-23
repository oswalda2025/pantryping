//
//  Product+Logic.swift
//  Pantry Ping
//

import Foundation

extension Product {
    var category: GroceryCategory {
        get { GroceryCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    // `flatMap` unwraps the optional raw string and converts it, giving nil if either fails.
    var servingUnit: MeasureUnit? {
        get { servingUnitRaw.flatMap(MeasureUnit.init(rawValue:)) }
        set { servingUnitRaw = newValue?.rawValue }
    }

    // Nutrition for one serving.
    var nutrition: NutritionFacts {
        get { NutritionFacts(calories: calories, carbs: carbs, protein: protein, fat: fat) }
        set {
            calories = newValue.calories
            carbs = newValue.carbs
            protein = newValue.protein
            fat = newValue.fat
        }
    }

    // "62 g", "1 cup" — or nil when the label's serving size wasn't entered.
    var servingDescription: String? {
        guard let servingSize, let servingUnit else { return nil }
        return Quantity.text(servingSize, unit: servingUnit)
    }

    var activePackages: [GroceryItem] {
        (packages ?? []).filter { $0.status == .active }
    }

    // Active packages, the one that expires first at the top (the suggested one to use).
    var activePackagesByExpiry: [GroceryItem] {
        GroceryItem.sortedByUrgency(activePackages, now: .now)
    }

    // A converter for a package stored in `baseUnit`.
    func converter(baseUnit: MeasureUnit) -> QuantityConverter {
        QuantityConverter(baseUnit: baseUnit, servingSize: servingSize, servingUnit: servingUnit)
    }

    // Which base unit a new package should be stored in, given the unit its size was typed in.
    // Prefers the serving's kind of unit, so "5 servings" of 62 g servings becomes 310 g.
    func packageBaseUnit(forEnteredUnit unit: MeasureUnit) throws -> MeasureUnit {
        let servingBase = (servingSize != nil) ? servingUnit?.baseUnit : nil
        if unit == .serving {
            return servingBase ?? .serving
        }
        guard let servingBase else {
            return unit.baseUnit
        }
        guard servingBase.dimension == unit.dimension else {
            throw InventoryError.noConversion(from: unit)
        }
        return servingBase
    }

    // Buying again always creates a NEW package; older packages are never changed.
    // `throws` means this can fail (e.g. an amount with no known conversion) — callers use `try`.
    func makePackage(
        amount: Double,
        unit: MeasureUnit,
        purchaseDate: Date,
        price: Decimal?,
        expirationDate: Date?,
        expirationSource: ExpirationSource = .entered,
        storageLocation: StorageLocation,
        notes: String = ""
    ) throws -> GroceryItem {
        guard amount > 0, amount.isFinite else { throw InventoryError.invalidAmount }
        let baseUnit = try packageBaseUnit(forEnteredUnit: unit)
        guard let baseAmount = converter(baseUnit: baseUnit).toBase(amount, from: unit) else {
            throw InventoryError.noConversion(from: unit)
        }
        let milli = Quantity.milli(baseAmount)
        guard milli > 0 else { throw InventoryError.invalidAmount }

        let package = GroceryItem(
            name: name,
            category: category,
            storageLocation: storageLocation,
            purchaseDate: purchaseDate,
            expirationDate: expirationDate,
            notes: notes
        )
        package.product = self
        package.quantityUnit = baseUnit
        package.startingAmountMilli = milli
        package.remainingAmountMilli = milli
        package.price = price
        package.expirationSource = expirationDate == nil ? .entered : expirationSource
        package.addEvent(.purchased, date: package.purchaseDate, detail: Quantity.text(baseAmount, unit: baseUnit))
        return package
    }
}
