//
//  MigrationPlan.swift
//  Pantry Ping
//

import Foundation
import SwiftData

// The rest of the app uses these short names. They always point at the NEWEST schema;
// when a SchemaV4 is added, only these lines change.
typealias GroceryItem = SchemaV3.GroceryItem
typealias Product = SchemaV3.Product
typealias UsageEntry = SchemaV3.UsageEntry
typealias FoodEvent = SchemaV3.FoodEvent
typealias PreparedMeal = SchemaV3.PreparedMeal
typealias MealIngredient = SchemaV3.MealIngredient
typealias ShoppingItem = SchemaV3.ShoppingItem

// Lists every schema version in order and how to move from each to the next.
enum PantryPingMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
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

    // V3 only adds two optional product fields (barcode, nutrition source), so SwiftData
    // can do it by itself — a "lightweight" migration with no custom code.
    static var migrateV2toV3: MigrationStage {
        .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)
    }

    // Runs while the database is at version 2, so it must use SchemaV2's types directly
    // (the short names above point at the newest version).
    static func upgradeV1Items(in context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<SchemaV2.GroceryItem>())
        // Items with the same name share one saved product, so "Buy again" works for them.
        var productsByName: [String: SchemaV2.Product] = [:]

        for item in items where item.product == nil {
            // V1 only had a whole-number count, so it becomes that many pieces.
            let count = Quantity.milli(max(item.quantity, 0))
            item.quantityUnitRaw = MeasureUnit.piece.rawValue
            item.startingAmountMilli = count
            item.remainingAmountMilli = count

            let key = item.name.lowercased()
            let product = productsByName[key] ?? {
                let newProduct = SchemaV2.Product(name: item.name)
                newProduct.categoryRaw = item.categoryRaw
                context.insert(newProduct)
                productsByName[key] = newProduct
                return newProduct
            }()
            item.product = product

            let event = SchemaV2.FoodEvent(kind: .purchased, date: item.purchaseDate, detail: "Added before version 2")
            event.package = item
        }
        try context.save()
    }
}
