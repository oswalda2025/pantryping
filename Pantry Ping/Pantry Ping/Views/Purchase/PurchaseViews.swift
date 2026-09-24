//
//  PurchaseViews.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

// Units a package's size can be typed in, given what the product's label says.
enum PackageUnits {
    static func options(servingSize: Double?, servingUnit: MeasureUnit?) -> [MeasureUnit] {
        if servingSize != nil, let servingUnit {
            // Only units that convert to the serving's kind (e.g. g, kg, oz, lb for 62 g servings).
            return [.serving] + servingUnit.sameDimensionUnits.filter { MeasureUnit.labelUnits.contains($0) }
        }
        return [.serving] + MeasureUnit.labelUnits
    }
}

// First purchase of something new: the product's details (name, photo, nutrition)
// plus this package. Saving creates both.
struct NewGroceryView: View {
    var showsCancel = false
    // What a barcode scan found (nil when typed by hand or not found).
    var lookup: FoodLookupResult?
    // A scanned barcode, saved with the product so it's recognized next time.
    var barcode: String?
    // Called with the new package after saving, so the presenter can close or react.
    var onSaved: (GroceryItem) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Product.name) private var products: [Product]

    @State private var product: ProductDraft
    @State private var package: PackageDraft
    @State private var errorMessage: String?
    @State private var lastAutoFill: String?
    // Blocks a second tap on Save from creating the product and package twice.
    @State private var isSaving = false

    @MainActor
    init(prefillName: String = "", showsCancel: Bool = false, lookup: FoodLookupResult? = nil,
         barcode: String? = nil, onSaved: @escaping (GroceryItem) -> Void) {
        self.showsCancel = showsCancel
        self.lookup = lookup
        self.barcode = barcode
        self.onSaved = onSaved

        var productDraft = lookup.map(ProductDraft.init(lookup:)) ?? ProductDraft(name: prefillName)
        if productDraft.barcode == nil { productDraft.barcode = barcode }
        _product = State(initialValue: productDraft)

        // Use the package size printed on the box when it's in the same kind of unit
        // as the serving (e.g. 510 g of 39 g servings).
        var packageDraft = PackageDraft(product: nil)
        if let lookup, let amount = lookup.packageAmount, let unit = lookup.packageUnit,
           unit.dimension == lookup.servingUnit.dimension {
            packageDraft.amountText = NumberInput.text(amount)
            packageDraft.unit = unit
        } else if lookup != nil {
            packageDraft.amountText = ""
            packageDraft.unit = .serving
        }
        _package = State(initialValue: packageDraft)
    }

    private var units: [MeasureUnit] {
        PackageUnits.options(servingSize: product.servingSize, servingUnit: product.servingUnit)
    }

    // An already-saved product with the same name, so we can offer "Buy again" instead.
    private var existingMatch: Product? {
        let name = product.trimmedName.lowercased()
        guard !name.isEmpty else { return nil }
        return products.first { $0.name.lowercased() == name }
    }

    var body: some View {
        Form {
            if let lookup {
                Section {
                    Label("Found in \(lookup.source.displayName). Check the details against your package — you can change anything.",
                          systemImage: "barcode.viewfinder")
                        .font(.callout)
                }
            } else if let barcode {
                Section {
                    Label("Barcode \(barcode) wasn't found in USDA or Open Food Facts. Add the details once and Pantry Ping will recognize it next time.",
                          systemImage: "barcode")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let match = existingMatch {
                Section {
                    NavigationLink {
                        BuyAgainView(product: match, barcode: barcode, onSaved: onSaved)
                    } label: {
                        Label("“\(match.name)” is already saved — buy it again instead", systemImage: "arrow.clockwise")
                    }
                }
            }

            ProductFields(draft: $product)
            PackageFields(draft: $package, units: units)

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("New Product")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(product.trimmedName.isEmpty || isSaving)
            }
        }
        // When "servings per package" is typed and the package size hasn't been edited by
        // hand, fill it in so the user doesn't type it twice. `lastAutoFill` lets it keep
        // following along as more digits are typed ("5" → "50").
        .onChange(of: product.servingsPerPackageText) { _, newValue in
            let untouched = lastAutoFill == nil
                ? (package.amountText == "1" || package.amountText.isEmpty)
                : package.amountText == lastAutoFill
            guard untouched else { return }
            if NumberInput.double(newValue) != nil {
                package.amountText = newValue
                package.unit = .serving
                lastAutoFill = newValue
            } else if lastAutoFill != nil {
                // Servings per package was cleared, so the size it filled in no longer applies.
                package.amountText = ""
                lastAutoFill = nil
            }
        }
        // Typing a serving size (e.g. 62 g) changes which units make sense. Rather than
        // silently turning the default "1 piece" into "1 serving", ask for the real size.
        .onChange(of: units) { _, newUnits in
            if !newUnits.contains(package.unit) {
                let weightOrVolume = product.servingSize != nil ? product.servingUnit.baseUnit : nil
                package.unit = weightOrVolume.flatMap { newUnits.contains($0) ? $0 : nil } ?? .serving
                if package.amountText == "1" && lastAutoFill == nil {
                    package.amountText = ""
                }
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        if let problem = product.problem ?? package.problem {
            errorMessage = problem
            return
        }
        let newProduct = Product(name: product.trimmedName, category: product.category)
        product.apply(to: newProduct)
        do {
            let newPackage = try newProduct.makePackage(
                amount: package.amount ?? 1,
                unit: package.unit,
                purchaseDate: package.purchaseDate,
                price: package.price,
                expirationDate: package.expirationDate,
                storageLocation: package.storageLocation,
                notes: package.notes
            )
            isSaving = true
            modelContext.insert(newProduct)
            modelContext.insert(newPackage)
            PackageDraft.rememberLocation(package.storageLocation)
            onSaved(newPackage)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// Buying a saved product again: only this package's details are asked for.
// The product's name, photo, serving size, and nutrition are reused as they are.
struct BuyAgainView: View {
    let product: Product
    var showsCancel = false
    // A barcode just scanned; saved onto the product if it doesn't have one yet,
    // so the next scan recognizes it.
    var barcode: String?
    var onSaved: (GroceryItem) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var package: PackageDraft
    @State private var errorMessage: String?
    // Blocks a second tap on Save from adding the package twice.
    @State private var isSaving = false

    init(product: Product, showsCancel: Bool = false, barcode: String? = nil,
         onSaved: @escaping (GroceryItem) -> Void) {
        self.product = product
        self.showsCancel = showsCancel
        self.barcode = barcode
        self.onSaved = onSaved
        _package = State(initialValue: PackageDraft(product: product))
    }

    var body: some View {
        Form {
            Section {
                ProductSummaryRow(product: product)
            } footer: {
                Text("Reusing this product's saved details. Edit the product to change them.")
            }

            PackageFields(
                draft: $package,
                units: PackageUnits.options(servingSize: product.servingSize, servingUnit: product.servingUnit)
            )

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Buy Again")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(isSaving)
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        if let problem = package.problem {
            errorMessage = problem
            return
        }
        do {
            let newPackage = try product.makePackage(
                amount: package.amount ?? 1,
                unit: package.unit,
                purchaseDate: package.purchaseDate,
                price: package.price,
                expirationDate: package.expirationDate,
                storageLocation: package.storageLocation,
                notes: package.notes
            )
            isSaving = true
            if product.barcode == nil, let barcode, !barcode.isEmpty {
                product.barcode = barcode
            }
            modelContext.insert(newPackage)
            PackageDraft.rememberLocation(package.storageLocation)
            onSaved(newPackage)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// Photo, name, serving, and nutrition summary of a saved product.
struct ProductSummaryRow: View {
    let product: Product

    var body: some View {
        HStack(spacing: 12) {
            ProductThumbnail(data: product.photoData, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.body.weight(.medium))
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts: [String] = []
        if let serving = product.servingDescription {
            parts.append("Serving \(serving)")
        }
        if let calories = product.calories {
            parts.append("\(Quantity.number(calories, maxFractionDigits: 0)) kcal")
        }
        if parts.isEmpty {
            parts.append(product.category.displayName)
        }
        return parts.joined(separator: " · ")
    }
}

// The "+" sheet: buy something you've bought before, or add a new product.
struct AddGroceryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Product.name) private var products: [Product]
    @State private var searchText = ""

    private var matchingProducts: [Product] {
        guard !searchText.isEmpty else { return products }
        return products.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ScanBarcodeView { _ in dismiss() }
                    } label: {
                        Label("Scan Barcode", systemImage: "barcode.viewfinder")
                    }
                    NavigationLink {
                        NewGroceryView(prefillName: searchText) { _ in dismiss() }
                    } label: {
                        Label("New Product", systemImage: "plus.circle.fill")
                    }
                }
                if !matchingProducts.isEmpty {
                    Section("Buy Again") {
                        ForEach(matchingProducts) { product in
                            NavigationLink {
                                BuyAgainView(product: product) { _ in dismiss() }
                            } label: {
                                ProductSummaryRow(product: product)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Groceries")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search saved products")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
