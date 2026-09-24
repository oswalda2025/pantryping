//
//  FoodState.swift
//  Pantry Ping
//

import Foundation

// What has happened to the food itself. Separate from where it's stored (StorageLocation)
// and from whether it's still in the kitchen (ItemStatus).
enum FoodState: String, CaseIterable, Identifiable {
    case fresh
    case opened
    case cooked
    case frozen
    case thawed

    var id: String { rawValue }

    // Past-tense label shown on an item, e.g. "Frozen".
    var displayName: String {
        switch self {
        case .fresh: "Fresh"
        case .opened: "Opened"
        case .cooked: "Cooked"
        case .frozen: "Frozen"
        case .thawed: "Thawed"
        }
    }

    // Verb shown on the button that moves an item INTO this state, e.g. "Freeze".
    var actionName: String {
        switch self {
        case .fresh: "Mark Fresh"
        case .opened: "Open"
        case .cooked: "Cook"
        case .frozen: "Freeze"
        case .thawed: "Thaw"
        }
    }

    var systemImage: String {
        switch self {
        case .fresh: "leaf"
        case .opened: "shippingbox.and.arrow.backward"
        case .cooked: "frying.pan"
        case .frozen: "snowflake"
        case .thawed: "drop"
        }
    }

    // The states a user can move to from this one. Refreezing thawed food is allowed
    // (fridge-thawed food can be refrozen), but its Freeze sheet shows a caution.
    var nextStates: [FoodState] {
        switch self {
        case .fresh: [.opened, .cooked, .frozen]
        case .opened: [.cooked, .frozen]
        case .cooked: [.frozen]
        case .frozen: [.thawed]
        case .thawed: [.cooked, .frozen]
        }
    }

    // Where the food normally ends up after this change. nil = leave the location alone.
    var impliedLocation: StorageLocation? {
        switch self {
        case .frozen: .freezer
        case .thawed, .cooked: .fridge
        case .fresh, .opened: nil
        }
    }

    // Opening doesn't make the package date meaningless, so it's kept by default.
    // Cooking, freezing, and thawing start a new timeline, so the old date is cleared
    // unless the user enters a new one — we never invent a duration.
    var keepsExistingDateByDefault: Bool {
        self == .opened
    }

    // General guidance shown when moving INTO this state. Deliberately free of specific
    // day counts: we only have the user's dates, not a verified food-storage database.
    func guidance(from previous: FoodState) -> String {
        switch self {
        case .fresh:
            return ""
        case .opened:
            return "Package dates usually apply before opening. Check the label for \"use within X days of opening\" and update the date if needed."
        case .cooked:
            return "The package date no longer applies to cooked food. Add a use-by date if you'd like a reminder — leftovers generally keep only a short time in the fridge."
        case .frozen:
            let base = "Freezing pauses food but doesn't reset it, and quality still declines over time. Optionally set a \"use by\" date for best quality."
            return previous == .thawed
                ? base + " Only refreeze food that was thawed in the fridge; quality may drop."
                : base
        case .thawed:
            return "Thawed food should be used fairly soon. Add a use-by date as a reminder, or check USDA's FoodKeeper app for typical times."
        }
    }

    // For a package date that has passed: many printed dates are about quality.
    static let expiredGuidance = "This date has passed. Many package dates are about quality rather than safety, so check how it looks and smells — when in doubt, throw it out."

    // For leftovers, thawed food, or a passed suggested date, "look and smell" is wrong advice:
    // the bacteria that make people sick usually can't be seen or smelled.
    static let expiredLeftoverGuidance = "Cooked leftovers and thawed food past their window should be thrown out — harmful bacteria usually can't be seen or smelled."

    static let disclaimer = "Pantry Ping shows the dates you enter, suggested dates from general USDA guidance, and nutrition from databases that can be wrong. It can't tell whether food is safe — check labels, use your judgment, or see foodsafety.gov."
}
