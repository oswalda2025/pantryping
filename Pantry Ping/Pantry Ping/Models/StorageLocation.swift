//
//  StorageLocation.swift
//  Pantry Ping
//

import Foundation

// An enum is a fixed set of choices. The `String` raw values ("fridge", ...) are what get
// saved to disk, so they must never be renamed once the app ships.
// `CaseIterable` provides `allCases`, which pickers and filters will use later.
enum StorageLocation: String, CaseIterable, Identifiable {
    case fridge
    case freezer
    case pantry

    // Identifiable lets SwiftUI lists and pickers tell each case apart.
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fridge: "Fridge"
        case .freezer: "Freezer"
        case .pantry: "Pantry"
        }
    }
}
