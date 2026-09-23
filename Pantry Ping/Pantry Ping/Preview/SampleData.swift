//
//  SampleData.swift
//  Pantry Ping
//

import Foundation
import SwiftData

// Demo groceries covering every urgency level and food state. Used by SwiftUI previews
// and by the "Try Sample Groceries" button, so the app can be explored without typing.
enum SampleData {
    // A throwaway in-memory database for #Preview canvases. `isStoredInMemoryOnly`
    // means nothing is written to disk.
    static let previewContainer: ModelContainer = {
        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: SchemaV1.self),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            insertSampleGroceries(into: container.mainContext)
            return container
        } catch {
            fatalError("Could not create preview container: \(error)")
        }
    }()

    // One item from the preview database, for previews of single-item screens.
    static var previewSampleItem: GroceryItem {
        let items = (try? previewContainer.mainContext.fetch(FetchDescriptor<GroceryItem>())) ?? []
        return items.first { $0.name == "Milk" } ?? GroceryItem(name: "Milk")
    }

    static func insertSampleGroceries(into context: ModelContext, now: Date = .now) {
        let calendar = Calendar.current
        // A small helper: a date `offset` days from today.
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: now) ?? now
        }

        let items: [GroceryItem] = [
            GroceryItem(name: "Strawberries", category: .produce, purchaseDate: day(-5), expirationDate: day(-1)),
            GroceryItem(name: "Spinach", category: .produce, purchaseDate: day(-4), expirationDate: day(0)),
            GroceryItem(name: "Milk", category: .dairyEggs, purchaseDate: day(-6), expirationDate: day(1)),
            GroceryItem(name: "Sourdough Bread", category: .bakery, storageLocation: .pantry, purchaseDate: day(-2), expirationDate: day(2)),
            GroceryItem(name: "Greek Yogurt", category: .dairyEggs, purchaseDate: day(-3), expirationDate: day(3)),
            GroceryItem(name: "Bell Peppers", category: .produce, quantity: 3, purchaseDate: day(-1), expirationDate: day(6)),
            GroceryItem(name: "Eggs", category: .dairyEggs, quantity: 12, purchaseDate: day(-2), expirationDate: day(18)),
            GroceryItem(name: "Rice", category: .dryCanned, storageLocation: .pantry, purchaseDate: day(-20)),
        ]

        let chicken = GroceryItem(name: "Chicken Breast", category: .meatSeafood, purchaseDate: day(-5), expirationDate: day(-3))
        chicken.changeFoodState(to: .frozen, newExpirationDate: nil, on: day(-4))

        let pasta = GroceryItem(name: "Pasta Bake", category: .leftovers, purchaseDate: day(-1))
        pasta.changeFoodState(to: .cooked, newExpirationDate: day(2), on: day(-1))

        for item in items + [chicken, pasta] {
            context.insert(item)
        }
    }
}
