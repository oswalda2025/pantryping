//
//  ShoppingListView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

// Things you plan to buy. Tapping "Buy" opens the purchase form; once the package is
// saved, the item leaves the list.
struct ShoppingListView: View {
    @Query(sort: \ShoppingItem.dateAdded) private var items: [ShoppingItem]
    @Query(sort: \Product.name) private var products: [Product]
    @Environment(\.modelContext) private var modelContext

    @State private var newItemName = ""
    @State private var itemToBuy: ShoppingItem?
    // Set when a purchase is saved; the item is removed once its sheet has closed.
    @State private var boughtItem: ShoppingItem?

    private var trimmedName: String {
        newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add an item", text: $newItemName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(addItem)
                        Button("Add", action: addItem)
                            .disabled(trimmedName.isEmpty)
                    }
                } footer: {
                    Text("Items matching a saved product reuse its details when you buy them.")
                }

                if !items.isEmpty {
                    Section("To Buy") {
                        ForEach(items) { item in
                            HStack(spacing: 12) {
                                if let product = item.product {
                                    ProductThumbnail(data: product.photoData, size: 36)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    if item.product != nil {
                                        Text("Saved product")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Buy") { itemToBuy = item }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("Buy \(item.name)")
                            }
                            .swipeActions {
                                Button("Remove", systemImage: "trash", role: .destructive) {
                                    withAnimation { modelContext.delete(item) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shopping List")
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Your list is empty",
                        systemImage: "cart",
                        description: Text("Add things you plan to buy, or use “Add to Shopping List” on any grocery.")
                    )
                    .offset(y: 60)
                }
            }
            .sheet(item: $itemToBuy, onDismiss: removeBoughtItem) { item in
                NavigationStack {
                    if let product = item.product {
                        BuyAgainView(product: product, showsCancel: true) { _ in markBought(item) }
                    } else {
                        NewGroceryView(prefillName: item.name, showsCancel: true) { _ in markBought(item) }
                    }
                }
            }
        }
    }

    private func addItem() {
        guard !trimmedName.isEmpty else { return }
        // Link to a saved product with the same name, so buying reuses its details.
        let match = products.first { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }
        withAnimation {
            modelContext.insert(ShoppingItem(name: match?.name ?? trimmedName, product: match))
        }
        newItemName = ""
    }

    private func markBought(_ item: ShoppingItem) {
        boughtItem = item
        itemToBuy = nil
    }

    private func removeBoughtItem() {
        if let boughtItem {
            withAnimation { modelContext.delete(boughtItem) }
            self.boughtItem = nil
        }
    }
}
