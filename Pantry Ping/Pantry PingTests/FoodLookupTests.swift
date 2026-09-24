//
//  FoodLookupTests.swift
//  Pantry PingTests
//

import Foundation
import SwiftData
import Testing
@testable import Pantry_Ping

// Barcode lookup parsing, tested against real responses captured from USDA FoodData
// Central and Open Food Facts (trimmed to the fields the app reads).
@MainActor
struct FoodLookupTests {
    // USDA search for Cheerios, barcode 016000275287 (stored by USDA as 00016000275287).
    static let usdaCheerios = #"{"totalHits":1,"foods":[{"description":"Cheerios Cereal","brandName":"Cheerios","brandOwner":"General Mills","gtinUpc":"00016000275287","servingSize":20.0,"servingSizeUnit":"GRM","packageWeight":"18 ONZ","foodNutrients":[{"nutrientId":1003,"nutrientName":"Protein","unitName":"G","value":12.8,"derivationDescription":"Given by information provider as an approximate value per 100 unit measure"},{"nutrientId":1004,"nutrientName":"Total lipid (fat)","unitName":"G","value":6.41,"derivationDescription":"Given by information provider as an approximate value per 100 unit measure"},{"nutrientId":1005,"nutrientName":"Carbohydrate, by difference","unitName":"G","value":74.4,"derivationDescription":"Given by information provider as an approximate value per 100 unit measure"},{"nutrientId":1008,"nutrientName":"Energy","unitName":"KCAL","value":359,"derivationDescription":"Given by information provider as an approximate value per 100 unit measure"},{"nutrientId":1003,"nutrientName":"Protein","unitName":"G","value":12.8,"derivationDescription":"Given by information provider as an approximate value per 100 unit measure"},{"nutrientId":1004,"nutrientName":"Total lipid (fat)","unitName":"G","value":6.41,"derivationDescription":"Given by information provider as an approximate value per 100 unit measure"},{"nutrientId":1005,"nutrientName":"Carbohydrate, by difference","unitName":"G","value":74.4,"derivationDescription":"Given by information provider as an approximate value per 100 unit measure"},{"nutrientId":1008,"nutrientName":"Energy","unitName":"KCAL","value":359,"derivationDescription":"Given by information provider as an approximate value per 100 unit measure"},{"nutrientId":1003,"nutrientName":"Protein","unitName":"G","value":5.56,"derivationDescription":"Calculated from an approximate value per serving size measure"},{"nutrientId":1004,"nutrientName":"Total lipid (fat)","unitName":"G","value":1.85,"derivationDescription":"Calculated from an approximate value per serving size measure"},{"nutrientId":1005,"nutrientName":"Carbohydrate, by difference","unitName":"G","value":21.6,"derivationDescription":"Calculated from an approximate value per serving size measure"},{"nutrientId":1008,"nutrientName":"Energy","unitName":"KCAL","value":117,"derivationDescription":"Calculated from an approximate value per serving size measure"}]}]}"#
    // Open Food Facts: Cheerios (per-serving values), Nutella (per-100 g only), and not found.
    static let offCheerios = #"{"status":1,"product":{"product_name":"Cheerios","brands":"Cheerios","serving_quantity":39,"serving_quantity_unit":"g","product_quantity":510.29141625,"product_quantity_unit":"g","nutriments":{"carbohydrates_100g":74.3589743589744,"carbohydrates_serving":29,"carbohydrates_unit":"g","carbohydrates_value":74.3589743589744,"energy-kcal_100g":358.974358974359,"energy-kcal_serving":140,"energy-kcal_unit":"kcal","energy-kcal_value":358.974358974359,"fat_100g":6.41025641025641,"fat_serving":2.5,"fat_unit":"g","fat_value":6.41025641025641,"proteins_100g":12.8205128205128,"proteins_serving":5,"proteins_unit":"g","proteins_value":12.8205128205128}}}"#
    static let offNutella = #"{"status":1,"product":{"product_name":"Nutella","brands":"Nutella, Ferrero","serving_quantity":null,"serving_quantity_unit":"g","product_quantity":400,"product_quantity_unit":"g","nutriments":{"carbohydrates_100g":57.5,"carbohydrates_unit":"g","carbohydrates_value":57.5,"energy-kcal_100g":539,"energy-kcal_unit":"kcal","energy-kcal_value":539,"fat_100g":30.9,"fat_unit":"g","fat_value":30.9,"proteins_100g":6.3,"proteins_unit":"g","proteins_value":6.3}}}"#
    static let offNotFound = #"{"status":0,"status_verbose":"no code or invalid code"}"#

    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test func barcodesCompareWithoutLeadingZeros() {
        #expect(FoodLookup.canonical("016000275287") == FoodLookup.canonical("00016000275287"))
        #expect(FoodLookup.canonical("0016000275287") == "16000275287")
        #expect(FoodLookup.gtin14("016000275287") == "00016000275287")
        #expect(FoodLookup.gtin14("3017620422003") == "03017620422003")
    }

    @Test func usdaResultIsPerServingFromTheLabelsOwnNumbers() throws {
        let result = try #require(try FoodLookup.parseUSDA(data(Self.usdaCheerios), barcode: "016000275287"))
        #expect(result.name == "Cheerios Cereal")
        #expect(result.source == .usda)
        #expect(result.servingSize == 20)
        #expect(result.servingUnit == .gram)
        // 359 kcal per 100 g × 20 g ÷ 100 — the "per 100" figure, not the later duplicates.
        #expect(abs((result.nutrition.calories ?? 0) - 71.8) < 0.001)
        #expect(abs((result.nutrition.protein ?? 0) - 2.56) < 0.001)
        // "18 ONZ" on the box.
        #expect(result.packageAmount == 18)
        #expect(result.packageUnit == .ounce)
    }

    @Test func usdaIgnoresResultsForADifferentBarcode() throws {
        #expect(try FoodLookup.parseUSDA(data(Self.usdaCheerios), barcode: "049000028911") == nil)
        #expect(try FoodLookup.parseUSDA(data(#"{"totalHits":0,"foods":[]}"#), barcode: "1234567890123") == nil)
    }

    @Test func openFoodFactsUsesPerServingValuesWhenGiven() throws {
        let result = try #require(try FoodLookup.parseOpenFoodFacts(data(Self.offCheerios), barcode: "016000275287"))
        #expect(result.name == "Cheerios")
        #expect(result.source == .openFoodFacts)
        #expect(result.servingSize == 39)
        #expect(result.nutrition == NutritionFacts(calories: 140, carbs: 29, protein: 5, fat: 2.5))
        #expect(result.packageUnit == .gram)
        #expect(abs((result.packageAmount ?? 0) - 510.29141625) < 0.0001)
    }

    @Test func openFoodFactsWithoutAServingUsesA100gServing() throws {
        let result = try #require(try FoodLookup.parseOpenFoodFacts(data(Self.offNutella), barcode: "3017620422003"))
        #expect(result.name == "Nutella")
        #expect(result.servingSize == 100)
        #expect(result.servingUnit == .gram)
        #expect(result.nutrition.calories == 539)
        #expect(result.packageAmount == 400)
    }

    // Live responses sometimes have only the text quantity, not the number.
    @Test func openFoodFactsFallsBackToTheQuantityText() throws {
        let json = #"{"status":1,"product":{"product_name":"Cheerios","quantity":"18 oz (510 g)","serving_quantity":39,"serving_quantity_unit":"g","nutriments":{"energy-kcal_serving":140}}}"#
        let result = try #require(try FoodLookup.parseOpenFoodFacts(data(json), barcode: "016000275287"))
        #expect(result.packageAmount == 510)
        #expect(result.packageUnit == .gram)
        #expect(result.nutrition.calories == 140)
        #expect(result.nutrition.protein == nil)
    }

    @Test func openFoodFactsNotFound() throws {
        #expect(try FoodLookup.parseOpenFoodFacts(data(Self.offNotFound), barcode: "000000000000") == nil)
    }

    @Test func packageSizesAndNames() {
        #expect(FoodLookup.parsePackageSize("18 oz/510 g")! == (510, .gram))
        #expect(FoodLookup.parsePackageSize("1.5 LB")! == (1.5, .pound))
        #expect(FoodLookup.parsePackageSize("12 FL OZ")! == (12, .fluidOunce))
        #expect(FoodLookup.parsePackageSize("family size") == nil)
        #expect(FoodLookup.productName(description: "PROTEIN GRANOLA", brand: "QUAKER") == "Quaker Protein Granola")
        #expect(FoodLookup.productName(description: "Cheerios Cereal", brand: "Cheerios") == "Cheerios Cereal")
    }

    // The source follows the numbers: untouched lookup values keep it, any edit makes it yours.
    @Test func editingLookedUpNutritionMakesItUserEntered() throws {
        let lookup = try #require(try FoodLookup.parseOpenFoodFacts(data(Self.offCheerios), barcode: "016000275287"))
        var draft = ProductDraft(lookup: lookup)
        #expect(draft.nutritionSource == .openFoodFacts)
        #expect(draft.barcode == "016000275287")
        draft.caloriesText = "150"
        #expect(draft.nutritionSource == .entered)
    }

    @Test func savedProductKeepsItsBarcodeAndSource() throws {
        let container = try ModelContainer(for: Schema(versionedSchema: SchemaV3.self),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let lookup = try #require(try FoodLookup.parseUSDA(data(Self.usdaCheerios), barcode: "016000275287"))
        let product = Product(name: "")
        ProductDraft(lookup: lookup).apply(to: product)
        context.insert(product)
        try context.save()

        let saved = try #require(try context.fetch(FetchDescriptor<Product>()).first)
        #expect(saved.barcode == "016000275287")
        #expect(saved.nutritionSource == .usda)
        #expect(saved.servingDescription == "20 g")
    }
}
