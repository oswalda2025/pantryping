//
//  InventoryEnums.swift
//  Pantry Ping
//

import Foundation

// Why some food was taken out of a package or meal.
// Only `.ate` counts toward the personal daily food log.
enum UsageReason: String, CaseIterable, Identifiable {
    case ate
    case mealPrep
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ate: "Ate"
        case .mealPrep: "Used in meal prep"
        case .other: "Other use"
        }
    }

    var systemImage: String {
        switch self {
        case .ate: "fork.knife"
        case .mealPrep: "takeoutbag.and.cup.and.straw"
        case .other: "ellipsis.circle"
        }
    }
}

// Where a use-by date came from. Suggested dates are always labeled as such,
// because general guidance is not a guarantee that food is safe.
enum ExpirationSource: String {
    case entered
    case suggested
}

// The kinds of lines that appear in a package's history.
enum FoodEventKind: String {
    case purchased, opened, cooked, frozen, thawed, moved, dateChanged
    case finished, discarded, restored, note

    var title: String {
        switch self {
        case .purchased: "Bought"
        case .opened: "Opened"
        case .cooked: "Cooked"
        case .frozen: "Frozen"
        case .thawed: "Thawed"
        case .moved: "Moved"
        case .dateChanged: "Use-by date changed"
        case .finished: "Finished"
        case .discarded: "Thrown away"
        case .restored: "Moved back to kitchen"
        case .note: "Note"
        }
    }

    var systemImage: String {
        switch self {
        case .purchased: "bag"
        case .opened: FoodState.opened.systemImage
        case .cooked: FoodState.cooked.systemImage
        case .frozen: FoodState.frozen.systemImage
        case .thawed: FoodState.thawed.systemImage
        case .moved: "arrow.right.circle"
        case .dateChanged: "calendar"
        case .finished: "checkmark.circle"
        case .discarded: "trash"
        case .restored: "arrow.uturn.backward"
        case .note: "note.text"
        }
    }
}
