//
//  FoodLookup.swift
//  Pantry Ping
//

import Foundation

// Where a product's nutrition numbers came from. Shown next to the numbers so database
// values are never mistaken for ones the user checked, and never presented as certain.
// Raw values are saved, so they must never be renamed.
nonisolated enum NutritionDataSource: String, Hashable {
    case entered
    case usda
    case openFoodFacts

    var displayName: String {
        switch self {
        case .entered: "Entered by you"
        case .usda: "USDA FoodData Central"
        case .openFoodFacts: "Open Food Facts"
        }
    }
}

// What a barcode lookup found: enough to pre-fill the New Product form.
// Nutrition is per ONE serving of `servingSize` `servingUnit`, like everywhere else.
nonisolated struct FoodLookupResult: Hashable {
    var barcode: String
    var name: String
    var servingSize: Double
    var servingUnit: MeasureUnit
    var nutrition: NutritionFacts
    // The package size printed on the box, when the database has it (e.g. 510 g).
    var packageAmount: Double?
    var packageUnit: MeasureUnit?
    var source: NutritionDataSource
}

// Looks a barcode up online: USDA FoodData Central first (official US label data),
// then Open Food Facts (worldwide, crowd-sourced). Only the barcode number is sent.
// The parsing functions are pure, so they're tested against real saved responses.
enum FoodLookup {
    enum Outcome: Equatable {
        case found(FoodLookupResult)
        case notFound
        case offline
    }

    // Without a personal key, USDA's shared demo key allows only a few lookups per hour.
    static let demoKey = "DEMO_KEY"
    static let usdaKeyStorageKey = "usdaAPIKey"

    // MARK: - Barcodes

    // Just the digits, without leading zeros — so "016000275287", "0016000275287" and
    // USDA's 14-digit "00016000275287" all compare equal.
    nonisolated static func canonical(_ barcode: String) -> String {
        let digits = barcode.filter(\.isNumber)
        let trimmed = digits.drop { $0 == "0" }
        return trimmed.isEmpty ? digits : String(trimmed)
    }

    // USDA stores barcodes as 14 digits padded with zeros (GTIN-14).
    nonisolated static func gtin14(_ barcode: String) -> String {
        let digits = barcode.filter(\.isNumber)
        return String(repeating: "0", count: max(0, 14 - digits.count)) + digits
    }

    // MARK: - Network

    static func lookup(_ barcode: String, usdaKey: String?) async -> Outcome {
        // UI tests use a fixed answer instead of the internet, so they're reliable.
        if ProcessInfo.processInfo.arguments.contains("-stubFoodLookup") {
            return stubbedOutcome(barcode)
        }
        let key = (usdaKey?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? demoKey
        var reachedAnyone = false

        // `async let` would run both at once, but USDA is preferred, so it goes first.
        switch await fetchUSDA(barcode, key: key) {
        case .success(let result?): return .found(result)
        case .success(nil): reachedAnyone = true
        case .failure: break
        }
        switch await fetchOpenFoodFacts(barcode) {
        case .success(let result?): return .found(result)
        case .success(nil): reachedAnyone = true
        case .failure: break
        }
        return reachedAnyone ? .notFound : .offline
    }

    private static func fetchUSDA(_ barcode: String, key: String) async -> Result<FoodLookupResult?, Error> {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: gtin14(barcode)),
            URLQueryItem(name: "dataType", value: "Branded"),
            URLQueryItem(name: "pageSize", value: "5"),
            URLQueryItem(name: "api_key", value: key),
        ]
        return await fetch(URLRequest(url: components.url!)) { data in
            try parseUSDA(data, barcode: barcode)
        }
    }

    private static func fetchOpenFoodFacts(_ barcode: String) async -> Result<FoodLookupResult?, Error> {
        let digits = barcode.filter(\.isNumber)
        // `quantity` (e.g. "18 oz (510 g)") must be requested for `product_quantity` to be sent.
        let fields = "product_name,brands,quantity,serving_quantity,serving_quantity_unit,product_quantity,product_quantity_unit,nutriments"
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=\(fields)") else {
            return .success(nil)
        }
        var request = URLRequest(url: url)
        // Open Food Facts asks apps to identify themselves.
        request.setValue("PantryPing/1.0 (iOS app)", forHTTPHeaderField: "User-Agent")
        return await fetch(request) { data in
            try parseOpenFoodFacts(data, barcode: barcode)
        }
    }

    // `await` pauses here until the server answers, without freezing the screen.
    private static func fetch(_ request: URLRequest,
                              parse: (Data) throws -> FoodLookupResult?) async -> Result<FoodLookupResult?, Error> {
        var request = request
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                return .success(nil)
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // e.g. 429 "too many requests" on the demo key — try the next database.
                return .failure(URLError(.badServerResponse))
            }
            return .success(try parse(data))
        } catch {
            return .failure(error)
        }
    }

    private static func stubbedOutcome(_ barcode: String) -> Outcome {
        guard canonical(barcode) == canonical("016000275287") else { return .notFound }
        return .found(FoodLookupResult(
            barcode: barcode, name: "Cheerios", servingSize: 39, servingUnit: .gram,
            nutrition: NutritionFacts(calories: 140, carbs: 29, protein: 5, fat: 2.5),
            packageAmount: 510, packageUnit: .gram, source: .openFoodFacts
        ))
    }

    // MARK: - Parsing USDA FoodData Central

    // `Decodable` structs mirror just the parts of the JSON we use.
    nonisolated private struct USDASearch: Decodable {
        struct Food: Decodable {
            let description: String?
            let brandName: String?
            let brandOwner: String?
            let gtinUpc: String?
            let servingSize: Double?
            let servingSizeUnit: String?
            let packageWeight: String?
            let foodNutrients: [Nutrient]?
        }
        struct Nutrient: Decodable {
            let nutrientId: Int?
            let unitName: String?
            let value: Double?
            let derivationDescription: String?
        }
        let foods: [Food]?
    }

    // USDA branded foods list nutrients per 100 g (or 100 ml), plus the label's serving
    // size, so one serving = value × servingSize ÷ 100. Only the label's own numbers are used.
    nonisolated static func parseUSDA(_ data: Data, barcode: String) throws -> FoodLookupResult? {
        let search = try JSONDecoder().decode(USDASearch.self, from: data)
        let wanted = canonical(barcode)
        guard let food = search.foods?.first(where: { canonical($0.gtinUpc ?? "") == wanted }) else {
            return nil
        }

        let per100 = NutritionFacts(
            calories: usdaValue(food, id: 1008, unit: "KCAL"),
            carbs: usdaValue(food, id: 1005, unit: "G"),
            protein: usdaValue(food, id: 1003, unit: "G"),
            fat: usdaValue(food, id: 1004, unit: "G")
        )

        // Serving from the label when it's in grams or ml; otherwise describe it as 100 g.
        let servingUnit: MeasureUnit?
        switch food.servingSizeUnit?.uppercased() {
        case "G", "GRM": servingUnit = .gram
        case "ML", "MLT": servingUnit = .milliliter
        default: servingUnit = nil
        }
        let serving: (Double, MeasureUnit)
        if let size = food.servingSize, size > 0, let servingUnit {
            serving = (size, servingUnit)
        } else {
            serving = (100, .gram)
        }

        let package = food.packageWeight.flatMap(parsePackageSize)
        return FoodLookupResult(
            barcode: barcode.filter(\.isNumber),
            name: productName(description: food.description, brand: food.brandName ?? food.brandOwner),
            servingSize: serving.0,
            servingUnit: serving.1,
            nutrition: per100.scaled(by: serving.0 / 100),
            packageAmount: package?.0,
            packageUnit: package?.1,
            source: .usda
        )
    }

    // The first value for a nutrient, preferring the "per 100 unit" figure the label gave.
    nonisolated private static func usdaValue(_ food: USDASearch.Food, id: Int, unit: String) -> Double? {
        let matches = (food.foodNutrients ?? []).filter {
            $0.nutrientId == id && $0.unitName?.uppercased() == unit && $0.value != nil
        }
        let per100 = matches.first { $0.derivationDescription?.localizedCaseInsensitiveContains("per 100") == true }
        return (per100 ?? matches.first)?.value
    }

    // MARK: - Parsing Open Food Facts

    nonisolated private struct OFFResponse: Decodable {
        struct Product: Decodable {
            let product_name: String?
            let brands: String?
            let serving_quantity: FlexibleNumber?
            let serving_quantity_unit: String?
            let product_quantity: FlexibleNumber?
            let product_quantity_unit: String?
            let quantity: String?
            let nutriments: [String: FlexibleNumber]?
        }
        let status: Int?
        let product: Product?
    }

    nonisolated static func parseOpenFoodFacts(_ data: Data, barcode: String) throws -> FoodLookupResult? {
        let response = try JSONDecoder().decode(OFFResponse.self, from: data)
        guard response.status == 1, let product = response.product,
              let rawName = product.product_name, !rawName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        let nutriments = product.nutriments ?? [:]
        func value(_ key: String, _ basis: String) -> Double? { nutriments["\(key)_\(basis)"]?.value }

        let servingUnit = unit(from: product.serving_quantity_unit ?? "g", allowed: [.gram, .milliliter])
        let servingSize = product.serving_quantity?.value
        let nutrition: NutritionFacts
        let serving: (Double, MeasureUnit)

        if let servingSize, servingSize > 0, let servingUnit,
           value("energy-kcal", "serving") != nil || value("proteins", "serving") != nil {
            // Per-serving values straight from the label.
            serving = (servingSize, servingUnit)
            nutrition = NutritionFacts(
                calories: value("energy-kcal", "serving"),
                carbs: value("carbohydrates", "serving"),
                protein: value("proteins", "serving"),
                fat: value("fat", "serving")
            )
        } else {
            let per100 = NutritionFacts(
                calories: value("energy-kcal", "100g"),
                carbs: value("carbohydrates", "100g"),
                protein: value("proteins", "100g"),
                fat: value("fat", "100g")
            )
            if let servingSize, servingSize > 0, let servingUnit {
                serving = (servingSize, servingUnit)
                nutrition = per100.scaled(by: servingSize / 100)
            } else {
                // No serving on the label: describe one "serving" as 100 g.
                serving = (100, .gram)
                nutrition = per100
            }
        }

        var package: (Double, MeasureUnit)?
        if let amount = product.product_quantity?.value, amount > 0,
           let unit = unit(from: product.product_quantity_unit ?? "g", allowed: [.gram, .milliliter]) {
            package = (amount, unit)
        } else if let text = product.quantity {
            package = parsePackageSize(text)
        }

        return FoodLookupResult(
            barcode: barcode.filter(\.isNumber),
            name: productName(description: rawName, brand: product.brands?.components(separatedBy: ",").first),
            servingSize: serving.0,
            servingUnit: serving.1,
            nutrition: nutrition,
            packageAmount: package?.0,
            packageUnit: package?.1,
            source: .openFoodFacts
        )
    }

    // Open Food Facts sometimes sends numbers as text ("39") and sometimes as numbers.
    nonisolated private struct FlexibleNumber: Decodable {
        let value: Double?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                value = number
            } else if let text = try? container.decode(String.self) {
                value = Double(text.replacingOccurrences(of: ",", with: "."))
            } else {
                value = nil
            }
        }
    }

    // MARK: - Shared helpers

    // "CHEERIOS CEREAL" → "Cheerios Cereal", with the brand added when the name lacks it.
    nonisolated static func productName(description: String?, brand: String?) -> String {
        func tidy(_ text: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed == trimmed.uppercased() ? trimmed.capitalized : trimmed
        }
        let name = tidy(description ?? "")
        guard let brand = brand.map(tidy), !brand.isEmpty else { return name }
        if name.isEmpty { return brand }
        return name.localizedCaseInsensitiveContains(brand) ? name : "\(brand) \(name)"
    }

    // "18 ONZ", "510 g", "18 oz/510 g" → the first usable size, preferring grams or ml.
    nonisolated static func parsePackageSize(_ text: String) -> (Double, MeasureUnit)? {
        let pattern = /([0-9]+(?:[.,][0-9]+)?)\s*(fl\.?\s*oz|onz|oz|lbs?|kg|grm|g|mlt|ml|l)\b/.ignoresCase()
        var found: [(Double, MeasureUnit)] = []
        for match in text.matches(of: pattern) {
            guard let number = Double(match.1.replacingOccurrences(of: ",", with: ".")),
                  let unit = unit(from: String(match.2), allowed: nil) else { continue }
            found.append((number, unit))
        }
        return found.first { $0.1 == .gram || $0.1 == .milliliter } ?? found.first
    }

    nonisolated private static func unit(from text: String, allowed: Set<MeasureUnit>?) -> MeasureUnit? {
        let key = text.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
        let unit: MeasureUnit? = switch key {
        case "g", "grm", "gram", "grams": .gram
        case "kg": .kilogram
        case "oz", "onz": .ounce
        case "lb", "lbs": .pound
        case "ml", "mlt": .milliliter
        case "l": .liter
        case "floz": .fluidOunce
        default: nil
        }
        guard let unit else { return nil }
        if let allowed, !allowed.contains(unit) { return nil }
        return unit
    }
}
