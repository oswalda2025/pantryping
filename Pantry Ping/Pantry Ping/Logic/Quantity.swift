//
//  Quantity.swift
//  Pantry Ping
//

import Foundation

// Amounts are stored as whole numbers of thousandths of a base unit ("milli-units"):
// 310 g is stored as 310_000. Adding and subtracting whole numbers is exact, so using
// 31 g ten times from a 310 g box lands on exactly 0 — no drifting 0.0000001 leftovers.
// Rounding happens only when an amount is turned into text.
enum Quantity {
    static let scale = 1000.0

    // Anything this large is a typo, and converting it to Int would crash.
    static let maximumValue = 1e12

    // Returns 0 for values that aren't usable (infinite, NaN, or absurdly large);
    // callers already treat 0 as "invalid amount".
    static func milli(_ value: Double) -> Int {
        guard value.isFinite, abs(value) < maximumValue else { return 0 }
        return Int((value * scale).rounded())
    }

    // Converting "1 portion" of a 3-portion meal gives 333.333…, so three portions would
    // leave 0.001 behind forever. An amount within a hair of what's left means "the rest".
    static func snapped(_ milli: Int, toRemaining remaining: Int, tolerance: Int = 5) -> Int {
        abs(milli - remaining) <= tolerance ? remaining : milli
    }

    static func value(_ milli: Int) -> Double {
        Double(milli) / scale
    }

    // "279", "4.5", "0.33" — trailing zeros dropped.
    static func number(_ value: Double, maxFractionDigits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFractionDigits)))
    }

    // "279 g", "4.5 servings", "1.5 cups"
    static func text(_ value: Double, unit: MeasureUnit) -> String {
        let digits: Int
        switch unit.dimension {
        case .mass, .volume: digits = 1
        case .count, .serving, .portion: digits = 2
        }
        return "\(number(value, maxFractionDigits: digits)) \(unit.label(for: value))"
    }
}

// Converts what a person types (e.g. "31 g" or "0.5 servings") into a package's base unit.
// It only ever uses standard unit definitions and the product's own serving size.
// When no conversion is known it returns nil — it never guesses.
struct QuantityConverter {
    // The unit the package's amounts are stored in: g, ml, piece, serving, or portion.
    let baseUnit: MeasureUnit
    // One serving, as printed on the label (optional).
    let servingSize: Double?
    let servingUnit: MeasureUnit?

    // How many base units make one serving, when the label tells us.
    var baseUnitsPerServing: Double? {
        if baseUnit == .serving { return 1 }
        guard let servingSize, let servingUnit, servingSize > 0,
              servingUnit.dimension == baseUnit.dimension else { return nil }
        return servingSize * servingUnit.factorToBase / baseUnit.factorToBase
    }

    // `value` in `unit`, expressed in the base unit — or nil if there's no known conversion.
    func toBase(_ value: Double, from unit: MeasureUnit) -> Double? {
        if unit == baseUnit {
            return value
        }
        // Same kind of unit (e.g. oz → g): a fixed, standard conversion.
        if unit.dimension == baseUnit.dimension {
            return value * unit.factorToBase / baseUnit.factorToBase
        }
        // Servings → grams (or ml, pieces) using the label's serving size.
        if unit == .serving, let perServing = baseUnitsPerServing {
            return value * perServing
        }
        // Grams → servings, for a package counted in servings whose product has a serving size.
        if baseUnit == .serving, let servingSize, let servingUnit, servingSize > 0,
           unit.dimension == servingUnit.dimension {
            return value * unit.factorToBase / (servingSize * servingUnit.factorToBase)
        }
        return nil
    }

    // An amount in the base unit, expressed as servings — or nil if unknown.
    func servings(fromBase value: Double) -> Double? {
        guard let perServing = baseUnitsPerServing else { return nil }
        return value / perServing
    }

    // The units someone can type an amount in for this package, most natural first.
    var enterableUnits: [MeasureUnit] {
        var units: [MeasureUnit] = []
        if baseUnitsPerServing != nil {
            units.append(.serving)
        }
        switch baseUnit.dimension {
        case .mass, .volume, .count:
            units += baseUnit.sameDimensionUnits
        case .serving:
            if let servingUnit, servingSize != nil {
                units += servingUnit.sameDimensionUnits
            }
        case .portion:
            units.append(.portion)
        }
        // Remove duplicates while keeping order.
        var seen = Set<MeasureUnit>()
        return units.filter { seen.insert($0).inserted }
    }

    // "279 g · 4.5 servings" — the base amount, plus servings when they're known and different.
    func text(forBase value: Double) -> String {
        let base = Quantity.text(value, unit: baseUnit)
        guard baseUnit != .serving, let servings = servings(fromBase: value) else { return base }
        return "\(base) · \(Quantity.text(servings, unit: .serving))"
    }
}
