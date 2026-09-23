//
//  MigrationPlan.swift
//  Pantry Ping
//

import Foundation
import SwiftData

// The rest of the app uses these short names. They always point at the NEWEST schema;
// when a SchemaV3 is added, only these lines change.
typealias GroceryItem = SchemaV2.GroceryItem
typealias Product = SchemaV2.Product
typealias UsageEntry = SchemaV2.UsageEntry
typealias FoodEvent = SchemaV2.FoodEvent
typealias PreparedMeal = SchemaV2.PreparedMeal
typealias MealIngredient = SchemaV2.MealIngredient
typealias ShoppingItem = SchemaV2.ShoppingItem

// Lists every schema version in order and how to move from each to the next.
enum PantryPingMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    // A custom stage: SwiftData first adds the new tables and columns automatically,
    // then `didMigrate` runs once to fill them in sensibly from the old data.
    static var migrateV1toV2: MigrationStage {
        .custom(
            fromVersion: SchemaV1.self,
            toVersion: SchemaV2.self,
            willMigrate: nil,
            didMigrate: { context in
                try upgradeV1Items(in: context)
            }
        )
    }

    // Separate from the stage so tests can run it on their own.
    static func upgradeV1Items(in context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<GroceryItem>())
        // Items with the same name share one saved product, so "Buy again" works for them.
        var productsByName: [String: Product] = [:]

        for item in items where item.product == nil {
            // V1 only had a whole-number count, so it becomes that many pieces.
            let count = max(item.quantity, 0)
            item.quantityUnitRaw = MeasureUnit.piece.rawValue
            item.startingAmountMilli = Quantity.milli(count)
            item.remainingAmountMilli = Quantity.milli(count)

            let key = item.name.lowercased()
            let product = productsByName[key] ?? {
                let newProduct = Product(name: item.name, category: item.category)
                context.insert(newProduct)
                productsByName[key] = newProduct
                return newProduct
            }()
            item.product = product

            item.addEvent(.purchased, date: item.purchaseDate, detail: "Added before version 2")
        }
        try context.save()
    }
}
