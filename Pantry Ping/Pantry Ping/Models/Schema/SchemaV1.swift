//
//  SchemaV1.swift
//  Pantry Ping
//

import Foundation
import SwiftData

// A VersionedSchema is a frozen snapshot of what the database looked like in version 1.
// DO NOT change the stored properties below: SwiftData compares them with a user's
// existing database to know it's a V1 store, then migrates it to the newest schema.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [GroceryItem.self]
    }

    @Model
    final class GroceryItem {
        var id: UUID = UUID()
        var name: String = ""
        var categoryRaw: String = "other"
        var storageLocationRaw: String = "fridge"
        var statusRaw: String = "active"
        var quantity: Double = 1
        var purchaseDate: Date = Date()
        var expirationDate: Date? = nil
        var originalExpirationDate: Date? = nil
        var foodStateRaw: String = "fresh"
        var dateOpened: Date? = nil
        var dateCooked: Date? = nil
        var dateFrozen: Date? = nil
        var dateThawed: Date? = nil
        var notes: String = ""
        var dateAdded: Date = Date()
        var dateResolved: Date? = nil

        // Only used by migration tests to create old-style data.
        init(name: String) {
            self.name = name
        }
    }
}
