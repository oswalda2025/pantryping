//
//  NutritionFacts.swift
//  Pantry Ping
//

import Foundation

// Calories and macros for some amount of food. Every value is optional: nil means
// "not entered", which is different from 0 — a missing value is never counted as zero.
nonisolated struct NutritionFacts: Hashable {
    var calories: Double?
    var carbs: Double?
    var protein: Double?
    var fat: Double?

    static let empty = NutritionFacts()

    var isEmpty: Bool {
        calories == nil && carbs == nil && protein == nil && fat == nil
    }

    // Nutrition for `factor` times this amount (e.g. 0.5 servings). Missing stays missing.
    func scaled(by factor: Double) -> NutritionFacts {
        NutritionFacts(
            calories: calories.map { $0 * factor },
            carbs: carbs.map { $0 * factor },
            protein: protein.map { $0 * factor },
            fat: fat.map { $0 * factor }
        )
    }
}

// Adds up nutrition from several foods while remembering which values were missing,
// so a total is never presented as exact when some food didn't have that value.
struct NutritionTotal {
    // A sum for one nutrient, plus how many items had no value for it.
    struct Part {
        var sum = 0.0
        var entered = 0
        var missing = 0

        mutating func add(_ value: Double?) {
            if let value {
                sum += value
                entered += 1
            } else {
                missing += 1
            }
        }

        // The exact total, or nil when any item is missing this value.
        var completeValue: Double? {
            missing == 0 && entered > 0 ? sum : nil
        }

        // "520 kcal", "520+ kcal (1 not entered)", or "not entered".
        func text(unit: String, digits: Int) -> String {
            let number = Quantity.number(sum, maxFractionDigits: digits)
            if entered == 0 { return "not entered" }
            if missing == 0 { return "\(number) \(unit)" }
            return "\(number)+ \(unit) (\(missing) not entered)"
        }
    }

    var calories = Part()
    var carbs = Part()
    var protein = Part()
    var fat = Part()
    var itemCount = 0

    mutating func add(_ facts: NutritionFacts) {
        calories.add(facts.calories)
        carbs.add(facts.carbs)
        protein.add(facts.protein)
        fat.add(facts.fat)
        itemCount += 1
    }

    // The total as facts, keeping only the values every item had.
    var completeFacts: NutritionFacts {
        NutritionFacts(
            calories: calories.completeValue,
            carbs: carbs.completeValue,
            protein: protein.completeValue,
            fat: fat.completeValue
        )
    }
}

// Display helpers shared by every screen that shows nutrition.
enum NutritionFormat {
    static func calories(_ value: Double?) -> String {
        value.map { "\(Quantity.number($0, maxFractionDigits: 0)) kcal" } ?? "not entered"
    }

    static func grams(_ value: Double?) -> String {
        value.map { "\(Quantity.number($0, maxFractionDigits: 1)) g" } ?? "not entered"
    }

    // "210 kcal · 30 g carbs · 10 g protein · 6 g fat", skipping values not entered.
    static func summary(_ facts: NutritionFacts) -> String? {
        var parts: [String] = []
        if let calories = facts.calories { parts.append("\(Quantity.number(calories, maxFractionDigits: 0)) kcal") }
        if let carbs = facts.carbs { parts.append("\(Quantity.number(carbs, maxFractionDigits: 1)) g carbs") }
        if let protein = facts.protein { parts.append("\(Quantity.number(protein, maxFractionDigits: 1)) g protein") }
        if let fat = facts.fat { parts.append("\(Quantity.number(fat, maxFractionDigits: 1)) g fat") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
