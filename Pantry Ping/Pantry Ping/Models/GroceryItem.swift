//
//  GroceryItem.swift
//  Pantry Ping
//

import Foundation

// An extension adds behavior to a type defined elsewhere. Computed properties here
// are not saved to disk, which keeps the schema files limited to stored data.
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

    var expirationSource: ExpirationSource {
        get { ExpirationSource(rawValue: expirationSourceRaw) ?? .entered }
        set { expirationSourceRaw = newValue.rawValue }
    }

    var quantityUnit: MeasureUnit {
        get { MeasureUnit(rawValue: quantityUnitRaw) ?? .piece }
        set { quantityUnitRaw = newValue.rawValue }
    }

    // The name shown everywhere: the product's name when there is one.
    var displayName: String {
        product?.name ?? name
    }

    // Adds a dated line to this package's history.
    func addEvent(_ kind: FoodEventKind, date: Date = .now, detail: String = "") {
        let event = FoodEvent(kind: kind, date: date, detail: detail)
        // Linking the event to this package also saves it: SwiftData inserts related objects.
        event.package = self
    }

    // Kept so existing code can keep calling `GroceryItem.calendarDay(...)`.
    static func calendarDay(_ date: Date, calendar: Calendar = .current) -> Date {
        CalendarDay.noon(date, calendar: calendar)
    }
}

// Expiration and purchase dates represent a calendar day, not a moment in time.
// We store them at 12:00 noon local time: a Date is a fixed instant, and a midnight
// value can slide into the previous day after a time-zone change. Noon survives
// shifts of up to ±11 hours and never lands on a daylight-saving transition.
enum CalendarDay {
    static func noon(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }
}
