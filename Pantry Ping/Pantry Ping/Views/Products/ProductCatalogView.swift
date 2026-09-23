//
//  ProductCatalogView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

// Every product you've saved, for buying again or adding to the shopping list.
struct ProductCatalogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Product.name) private var products: [Product]
    @State private var searchText = ""
    @State private var productToBuy: Product?

    private var matchingProducts: [Product] {
        guard !searchText.isEmpty else { return products }
        return products.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(matchingProducts) { product in
                    NavigationLink {
                        ProductDetailView(product: product)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            ProductSummaryRow(product: product)
                            let count = product.activePackages.count
                            if count > 0 {
                                Text("\(count) in your kitchen")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Buy Again", systemImage: "arrow.clockwise") { productToBuy = product }
                            .tint(.blue)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Add to List", systemImage: "cart.badge.plus") {
                            ShoppingList.add(product, in: modelContext)
                        }
                        .tint(.orange)
                    }
                }
            }
            .navigationTitle("Saved Products")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search products")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if products.isEmpty {
                    ContentUnavailableView(
                        "No saved products yet",
                        systemImage: "square.grid.2x2",
                        description: Text("Products are saved the first time you add a grocery, so buying again is quick.")
                    )
                }
            }
            .sheet(item: $productToBuy) { product in
                NavigationStack {
                    BuyAgainView(product: product, showsCancel: true) { _ in productToBuy = nil }
                }
            }
        }
    }
}

// One product: photo, serving, nutrition, and every package bought of it.
struct ProductDetailView: View {
    let product: Product

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.now) private var now
    @State private var isBuying = false
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var message: String?

    private var pastPackages: [GroceryItem] {
        (product.packages ?? [])
            .filter { $0.status != .active }
            .sorted { $0.purchaseDate > $1.purchaseDate }
    }

    var body: some View {
        if product.isDeleted || product.modelContext == nil {
            ContentUnavailableView("Product deleted", systemImage: "trash")
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                if let photo = product.photoData {
                    ProductThumbnail(data: photo, size: 160)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                LabeledContent("Category", value: product.category.displayName)
                LabeledContent("Serving", value: product.servingDescription ?? "not entered")
                if let servings = product.servingsPerPackage {
                    LabeledContent("Servings per package", value: Quantity.number(servings, maxFractionDigits: 2))
                }
            }

            Section("Nutrition per serving") {
                LabeledContent("Calories", value: NutritionFormat.calories(product.calories))
                LabeledContent("Carbohydrates", value: NutritionFormat.grams(product.carbs))
                LabeledContent("Protein", value: NutritionFormat.grams(product.protein))
                LabeledContent("Fat", value: NutritionFormat.grams(product.fat))
            }

            Section {
                Button("Buy Again", systemImage: "arrow.clockwise") { isBuying = true }
                Button("Add to Shopping List", systemImage: "cart.badge.plus") {
                    message = ShoppingList.add(product, in: modelContext)
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }

            if !product.activePackagesByExpiry.isEmpty {
                Section("In Your Kitchen") {
                    ForEach(product.activePackagesByExpiry) { package in
                        NavigationLink {
                            GroceryDetailView(item: package)
                        } label: {
                            packageRow(package)
                        }
                    }
                }
            }

            if !pastPackages.isEmpty {
                Section("Past Packages") {
                    ForEach(pastPackages) { package in
                        NavigationLink {
                            GroceryDetailView(item: package)
                        } label: {
                            packageRow(package)
                        }
                    }
                }
            }

            Section {
                Button("Delete Product", role: .destructive) { isConfirmingDelete = true }
            } footer: {
                Text("Packages you've bought stay in your kitchen and history.")
            }
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { isEditing = true }
        }
        .sheet(isPresented: $isBuying) {
            NavigationStack {
                BuyAgainView(product: product, showsCancel: true) { _ in isBuying = false }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditProductView(product: product)
        }
        .confirmationDialog("Delete \(product.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(product)
                dismiss()
            }
        }
    }

    private func packageRow(_ package: GroceryItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Bought \(package.purchaseDate.formatted(date: .abbreviated, time: .omitted))")
            Text(package.status == .active
                 ? "\(package.remainingText) left · \(package.freshnessText(now: now))"
                 : package.status.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// Adding to the shopping list from several screens goes through one place,
// so duplicates are handled the same way everywhere.
enum ShoppingList {
    @discardableResult
    static func add(_ product: Product, in context: ModelContext) -> String {
        if !(product.shoppingItems ?? []).isEmpty {
            return "Already on your shopping list."
        }
        context.insert(ShoppingItem(name: product.name, product: product))
        return "Added to your shopping list."
    }
}
