//
//  ItemStatus.swift
//  Pantry Ping
//

import Foundation

// Where an item is in its lifecycle. This is NOT freshness: "expired" is calculated from
// the expiration date, and food state (opened, frozen, ...) will be a separate field later.
// Used and discarded items are kept rather than deleted so food-waste stats are possible.
enum ItemStatus: String, CaseIterable, Identifiable {
    case active
    case used
    case discarded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active: "In Stock"
        case .used: "Finished"
        case .discarded: "Thrown Away"
        }
    }
}
