//
//  StorageGuidance.swift
//  Pantry Ping
//

import Foundation

// A suggested use-by timeline from general guidance. It is only applied when the user
// taps "Use suggestion", and the resulting date stays labeled "suggested" everywhere.
struct StorageSuggestion: Equatable {
    let days: Int
    let message: String
    let source: String

    func date(from start: Date, calendar: Calendar = .current) -> Date {
        CalendarDay.noon(calendar.date(byAdding: .day, value: days, to: start) ?? start, calendar: calendar)
    }
}

// Deliberately tiny: suggestions exist only where USDA publishes a clear, general rule,
// and each uses the conservative (shortest) end of the range. Reviewed by the food-safety
// reviewer. Everything else relies on the dates the user enters.
enum StorageGuidance {
    static let source = "USDA FSIS"

    // Shown beside every suggested date.
    static let caveat = "General guidance for food kept at 40°F (4°C) or below, not a safety guarantee. When in doubt, throw it out."

    static let freezerNote = "Food kept frozen at 0°F (−18°C) the whole time stays safe, but quality declines over time."

    private static let leftovers = StorageSuggestion(
        days: 3,
        message: "Cooked leftovers generally keep 3–4 days in the fridge. Suggested: 3 days.",
        source: source
    )

    // Suggestion when an item moves into `newState`, or nil when there's no general rule.
    // Freezing never gets one: frozen food's limit is quality, not a date.
    static func suggestion(for newState: FoodState, category: GroceryCategory) -> StorageSuggestion? {
        switch newState {
        case .cooked:
            return leftovers
        case .thawed where category == .meatSeafood:
            return StorageSuggestion(
                days: 1,
                message: "Thawed in the fridge, ground meat, poultry, and seafood generally keep 1–2 days. Suggested: 1 day. Thawed in cold water or the microwave? Cook it right away.",
                source: source
            )
        default:
            return nil
        }
    }

    // Meal-prep batches follow the leftovers rule when refrigerated.
    static func suggestion(forPreparedMealIn storage: StorageLocation) -> StorageSuggestion? {
        storage == .fridge ? leftovers : nil
    }
}
