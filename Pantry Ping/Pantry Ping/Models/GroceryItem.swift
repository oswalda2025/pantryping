//
//  GroceryItem.swift
//  Pantry Ping
//

import Foundation
import SwiftData

// A VersionedSchema is a frozen snapshot of what the database looks like in version 1.
// When the model changes in a way SwiftData can't handle automatically, we add SchemaV2
// and a migration stage — this snapshot is what lets existing users' data upgrade safely.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [GroceryItem.self]
    }

    // @Model turns this class into something SwiftData saves on-device.
    // It's a `class` (not a struct) because SwiftData tracks and updates each item in place.
    //
    // Every stored property has a default value right here in its declaration. That lets
    // SwiftData add new properties later without crashing on launch, and keeps iCloud sync possible.
    @Model
    final class GroceryItem {
        // Our own stable ID. Future notification identifiers will be built from it.
        var id: UUID = UUID()
        var name: String = ""

        // Enums are saved as their raw String. Use the `category`, `storageLocation`,
        // and `status` accessors below instead of touching these directly.
        var categoryRaw: String = "other"
        var storageLocationRaw: String = "fridge"
        var statusRaw: String = "active"

        // Double so fractional amounts (0.5) work once units are added.
        var quantity: Double = 1

        var purchaseDate: Date = Date()

        // `Date?` is an optional: it may hold a date or be `nil`.
        // nil means "no known use-by date" (common for pantry staples).
        // This is the CURRENT use-by date the countdown uses. It may change when the food
        // is cooked, frozen, or thawed — but only to a date the user enters.
        var expirationDate: Date? = nil

        // The date entered when the item was added (usually the package date).
        // Food-state changes never touch it, so the original information is never lost.
        var originalExpirationDate: Date? = nil

        var foodStateRaw: String = "fresh"
        var dateOpened: Date? = nil
        var dateCooked: Date? = nil
        var dateFrozen: Date? = nil
        var dateThawed: Date? = nil

        var notes: String = ""

        var dateAdded: Date = Date()

        // Set when the item is marked Used or Thrown Away.
        var dateResolved: Date? = nil

        init(
            name: String,
            category: GroceryCategory = .other,
            storageLocation: StorageLocation = .fridge,
            quantity: Double = 1,
            purchaseDate: Date = .now,
            expirationDate: Date? = nil,
            notes: String = ""
        ) {
            self.name = name
            self.categoryRaw = category.rawValue
            self.storageLocationRaw = storageLocation.rawValue
            self.quantity = quantity
            self.purchaseDate = GroceryItem.calendarDay(purchaseDate)
            // `.map` runs only when the optional holds a value; nil stays nil.
            let day = expirationDate.map { GroceryItem.calendarDay($0) }
            self.expirationDate = day
            self.originalExpirationDate = day
            self.notes = notes
            self.dateAdded = .now
        }
    }
}

// Lets the rest of the app just write `GroceryItem` instead of `SchemaV1.GroceryItem`.
// When a SchemaV2 exists, this line moves to point at the newest version.
typealias GroceryItem = SchemaV1.GroceryItem

// Lists every schema version in order and how to move between them.
// Empty for now because there is only one version.
enum PantryPingMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

// An extension adds behavior to a type defined elsewhere. Computed properties here
// are not saved to disk, which keeps the SchemaV1 snapshot above limited to stored data.
extension GroceryItem {
    // Unknown raw values (e.g. from corrupted data) fall back to a safe default instead of crashing.
    var category: GroceryCategory {
        get { GroceryCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var storageLocation: StorageLocation {
        get { StorageLocation(rawValue: storageLocationRaw) ?? .fridge }
        set { storageLocationRaw = newValue.rawValue }
    }

    var foodState: FoodState {
        get { FoodState(rawValue: foodStateRaw) ?? .fresh }
        set { foodStateRaw = newValue.rawValue }
    }

    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .active }
        set {
            statusRaw = newValue.rawValue
            // Record when the item left the kitchen; clear it if it's restored to active.
            dateResolved = newValue == .active ? nil : .now
        }
    }

    // Expiration and purchase dates represent a calendar day, not a moment in time.
    // We store them at 12:00 noon local time: a Date is a fixed instant, and a midnight
    // value can slide into the previous day after a time-zone change. Noon survives
    // shifts of up to ±11 hours and never lands on a daylight-saving transition.
    static func calendarDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }
}
