//
//  MeasureUnit.swift
//  Pantry Ping
//

import Foundation

// `nonisolated` lets this plain value type be used from any thread, not just the main one.
// Units a food can be measured in. Units within the same dimension (e.g. g and oz)
// convert using fixed, standard definitions. Units in DIFFERENT dimensions (e.g. g and
// cups) are never converted: that would need the food's density, which we don't know.
nonisolated enum MeasureUnit: String, CaseIterable, Identifiable {
    case gram = "g"
    case kilogram = "kg"
    case ounce = "oz"
    case pound = "lb"
    case milliliter = "ml"
    case liter = "l"
    case cup
    case tablespoon = "tbsp"
    case teaspoon = "tsp"
    case fluidOunce = "floz"
    case piece
    case serving
    case portion

    // A nested enum groups the units that can convert into each other.
    enum Dimension {
        case mass, volume, count, serving, portion
    }

    var id: String { rawValue }

    var dimension: Dimension {
        switch self {
        case .gram, .kilogram, .ounce, .pound: .mass
        case .milliliter, .liter, .cup, .tablespoon, .teaspoon, .fluidOunce: .volume
        case .piece: .count
        case .serving: .serving
        case .portion: .portion
        }
    }

    // How many of the dimension's base unit (g, ml, piece) one of this unit is.
    // These are exact standard definitions (US customary for cups and spoons).
    var factorToBase: Double {
        switch self {
        case .gram, .milliliter, .piece, .serving, .portion: 1
        case .kilogram, .liter: 1000
        case .ounce: 28.349523125
        case .pound: 453.59237
        case .cup: 236.5882365
        case .tablespoon: 14.78676478125
        case .teaspoon: 4.92892159375
        case .fluidOunce: 29.5735295625
        }
    }

    // The unit amounts of this dimension are stored in.
    var baseUnit: MeasureUnit {
        switch dimension {
        case .mass: .gram
        case .volume: .milliliter
        case .count: .piece
        case .serving: .serving
        case .portion: .portion
        }
    }

    // Units that appear on labels, offered when describing a serving or a package.
    static let labelUnits: [MeasureUnit] = [
        .gram, .kilogram, .ounce, .pound,
        .milliliter, .liter, .cup, .tablespoon, .teaspoon, .fluidOunce,
        .piece,
    ]

    // Other units in the same dimension, e.g. [g, kg, oz, lb] for grams.
    var sameDimensionUnits: [MeasureUnit] {
        MeasureUnit.allCases.filter { $0.dimension == dimension }
    }

    // "g", "cup"/"cups", "serving"/"servings"
    func label(for amount: Double) -> String {
        let isOne = abs(amount - 1) < 0.0001
        switch self {
        case .gram, .kilogram, .ounce, .pound, .milliliter, .liter, .tablespoon, .teaspoon:
            return rawValue
        case .fluidOunce: return "fl oz"
        case .cup: return isOne ? "cup" : "cups"
        case .piece: return isOne ? "piece" : "pieces"
        case .serving: return isOne ? "serving" : "servings"
        case .portion: return isOne ? "portion" : "portions"
        }
    }

    // Name for pickers.
    var pickerName: String {
        switch self {
        case .gram: "grams (g)"
        case .kilogram: "kilograms (kg)"
        case .ounce: "ounces (oz)"
        case .pound: "pounds (lb)"
        case .milliliter: "milliliters (ml)"
        case .liter: "liters (l)"
        case .cup: "cups"
        case .tablespoon: "tablespoons (tbsp)"
        case .teaspoon: "teaspoons (tsp)"
        case .fluidOunce: "fluid ounces (fl oz)"
        case .piece: "pieces"
        case .serving: "servings"
        case .portion: "portions"
        }
    }
}
