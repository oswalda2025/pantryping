//
//  GroceryDetailView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

// Everything about one purchased package, plus the actions that change it:
// Use Some, Finished, Threw Away, food-state changes, Buy Again, edit, and delete.
struct GroceryDetailView: View {
    // SwiftData models are observable: when a property of `item` changes,
    // this view redraws automatically — no @State needed.
    let item: GroceryItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.now) private var now

    @State private var sheet: DetailSheet?
    @State private var isConfirmingDelete = false
    // Deleting waits until this screen has closed, so it never shows a deleted item.
    @State private var deleteWhenClosed = false
    @State private var shoppingListMessage: String?
    // A use-up the user asked to undo, waiting for confirmation.
    @State private var usageToUndo: UsageEntry?

    // Every sheet this screen can show. One enum means two sheets can't collide.
    private enum DetailSheet: Identifiable {
        case editPackage, editProduct, useSome, buyAgain, updateDate
        case stateChange(FoodState)

        var id: String {
            switch self {
            case .stateChange(let state): "state-\(state.rawValue)"
            default: "\(self)"
            }
        }
    }

    var body: some View {
        // The item may have been deleted elsewhere (e.g. from another tab) while this
        // screen was still open. Reading a deleted SwiftData model can crash, so check first.
        if item.isDeleted || item.modelContext == nil {
            ContentUnavailableView("Grocery deleted", systemImage: "trash")
        } else {
            details
        }
    }

    @ViewBuilder
    private var details: some View {
        let status = item.expirationStatus(now: now)

        List {
            headerSection(status: status)

            if item.status == .active {
                actionsSection
                foodStateSection
            } else {
                resolvedSection
            }

            productSection
            detailsSection
            historySection

            Section {
                Button("Delete Grocery", role: .destructive) {
                    isConfirmingDelete = true
                }
            } footer: {
                Text("Deleting removes it completely. To keep your history, use Finished or Threw Away instead.")
            }
        }
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { sheet = .editPackage }
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .confirmationDialog("Delete \(item.displayName)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteWhenClosed = true
                dismiss()
            }
        }
        .onDisappear {
            if deleteWhenClosed {
                item.delete(in: modelContext)
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: DetailSheet) -> some View {
        switch sheet {
        case .editPackage:
            EditPackageView(item: item)
        case .editProduct:
            if let product = item.product {
                EditProductView(product: product)
            }
        case .useSome:
            UseSomeSheet(package: item)
        case .buyAgain:
            NavigationStack {
                if let product = item.product {
                    BuyAgainView(product: product, showsCancel: true) { _ in self.sheet = nil }
                }
            }
        case .updateDate:
            UseByDateSheet(item: item, newState: nil)
        case .stateChange(let state):
            UseByDateSheet(item: item, newState: state)
        }
    }

    // MARK: - Sections

    private func headerSection(status: ExpirationStatus) -> some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                if item.product?.photoData != nil {
                    ProductThumbnail(data: item.product?.photoData, size: 64)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(item.freshnessText(now: now)).foregroundStyle(status.textColor)
                    } icon: {
                        Image(systemName: status.systemImage).foregroundStyle(status.tint)
                    }
                    .font(.title3.weight(.semibold))
                    Text(summaryLine)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            if item.hasMeaningfulAmount {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(item.remainingText) left")
                        .font(.headline)
                    ProgressView(value: Double(item.remainingAmountMilli), total: Double(max(item.startingAmountMilli, 1)))
                        .accessibilityHidden(true)
                    Text("of \(item.startingText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            if item.expirationSource == .suggested, item.expirationDate != nil {
                HStack(alignment: .top) {
                    SuggestedTag()
                    Text(StorageGuidance.caveat)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if item.status == .active && (status == .expired || item.shouldSuggestUseByDate) {
                VStack(alignment: .leading, spacing: 8) {
                    if status == .expired {
                        Text(item.pastDateGuidance)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Button(status != .expired ? "Add a Use-By Date"
                           : item.isPastDateRisky ? "Update Date" : "Still Have It — Update Date") {
                        sheet = .updateDate
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button("Use Some", systemImage: "minus.circle") {
                sheet = .useSome
            }
            Button("Finished", systemImage: "checkmark.circle") {
                item.finish()
                dismiss()
            }
            .tint(.green)
            Button("Threw Away", systemImage: "trash") {
                item.throwAway()
                dismiss()
            }
            .tint(.red)
        } footer: {
            Text("Finished and thrown-away items leave your kitchen and stop reminders, but stay in History.")
        }
    }

    private var foodStateSection: some View {
        Section {
            // One button per state this food can move to next, e.g. Freeze or Thaw.
            ForEach(item.foodState.nextStates) { state in
                Button(state.actionName, systemImage: state.systemImage) {
                    sheet = .stateChange(state)
                }
            }
        } header: {
            Text("Food State: \(item.foodState.displayName)")
        }
    }

    private var resolvedSection: some View {
        Section {
            if let resolved = item.dateResolved {
                LabeledContent(item.status.displayName, value: resolved.formatted(date: .abbreviated, time: .omitted))
            }
            if item.canRestoreToKitchen {
                Button("Move Back to Kitchen", systemImage: "arrow.uturn.backward") {
                    item.restoreToKitchen()
                }
            } else if item.remainingAmountMilli == 0 {
                Text("All of it was used, so there's nothing to move back. To put an amount back, swipe left on a use in History below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var productSection: some View {
        Section {
            if let product = item.product {
                if let serving = product.servingDescription {
                    LabeledContent("Serving", value: serving)
                }
                if !product.nutrition.isEmpty {
                    LabeledContent("Calories", value: NutritionFormat.calories(product.calories))
                    LabeledContent("Carbohydrates", value: NutritionFormat.grams(product.carbs))
                    LabeledContent("Protein", value: NutritionFormat.grams(product.protein))
                    LabeledContent("Fat", value: NutritionFormat.grams(product.fat))
                }
                Button("Edit Product", systemImage: "pencil") { sheet = .editProduct }
            }
            Button("Buy Again", systemImage: "arrow.clockwise") {
                // Make sure a product exists before the sheet appears (older items may lack one).
                _ = ensureProduct()
                sheet = .buyAgain
            }
            Button("Add to Shopping List", systemImage: "cart.badge.plus", action: addToShoppingList)
            if let shoppingListMessage {
                Text(shoppingListMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(item.product?.nutrition.isEmpty == false ? "Product · per serving" : "Product")
        } footer: {
            if let source = item.product?.nutritionSource, source != .entered {
                Text("Nutrition from \(source.displayName) — check against your package.")
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            if item.hasMeaningfulAmount {
                LabeledContent("Package size", value: item.startingText)
            }
            if let price = item.price {
                LabeledContent("Price", value: Money.text(price))
            }
            if let date = item.expirationDate {
                LabeledContent {
                    HStack {
                        if item.expirationSource == .suggested { SuggestedTag() }
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                    }
                } label: {
                    Text("Use by")
                }
            } else {
                LabeledContent("Use by", value: "No date")
            }
            if item.originalExpirationDate != item.expirationDate {
                dateRow("Original date", item.originalExpirationDate, fallback: "None")
            }
            dateRow("Purchased", item.purchaseDate)
            dateRow("Opened", item.dateOpened)
            dateRow("Cooked", item.dateCooked)
            dateRow("Frozen", item.dateFrozen)
            dateRow("Thawed", item.dateThawed)
            if !item.notes.isEmpty {
                LabeledContent("Notes", value: item.notes)
            }
        }
    }

    // Events (bought, frozen, moved...) and usage merged into one timeline, newest first.
    private var historySection: some View {
        Section {
            ForEach(timeline) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: entry.systemImage)
                        .foregroundStyle(.tint)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                        if !entry.detail.isEmpty {
                            Text(entry.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                // Any use-up (eaten, meal prep, or other) can be undone here to fix mistakes.
                .swipeActions {
                    if let usage = entry.usage {
                        Button("Undo", systemImage: "arrow.uturn.backward") { usageToUndo = usage }
                            .tint(.orange)
                    }
                }
            }
        } header: {
            Text("History")
        } footer: {
            if item.usageEntries?.isEmpty == false {
                Text("Swipe left on a use to undo it and put the amount back.")
            }
        }
        .confirmationDialog(
            "Put \(usageToUndo?.amountText ?? "it") back?",
            isPresented: Binding(get: { usageToUndo != nil }, set: { if !$0 { usageToUndo = nil } }),
            titleVisibility: .visible,
            presenting: usageToUndo
        ) { usage in
            Button("Undo This Use", role: .destructive) {
                withAnimation { usage.undo(in: modelContext) }
            }
        } message: { usage in
            Text(usage.reason == .mealPrep
                 ? "The amount goes back into this package. The meal it was used in keeps its ingredient list."
                 : "The amount goes back into this package and the entry is removed.")
        }
    }

    private struct TimelineEntry: Identifiable {
        // A stable identity (the database ID), so rows don't redraw as new ones every time.
        let id: PersistentIdentifier
        let date: Date
        let systemImage: String
        let title: String
        let detail: String
        var usage: UsageEntry?
    }

    private var timeline: [TimelineEntry] {
        let events = (item.events ?? []).map { event in
            let kind = FoodEventKind(rawValue: event.kindRaw) ?? .note
            return TimelineEntry(id: event.persistentModelID, date: event.date, systemImage: kind.systemImage,
                                 title: kind.title, detail: event.detail)
        }
        let uses = (item.usageEntries ?? []).map { entry in
            TimelineEntry(id: entry.persistentModelID, date: entry.date, systemImage: entry.reason.systemImage,
                          title: "Used \(entry.amountText)", detail: entry.reason.displayName, usage: entry)
        }
        return (events + uses).sorted { $0.date > $1.date }
    }

    // "Pantry · Dry & Canned Goods"
    private var summaryLine: String {
        var parts = [item.storageLocation.displayName, item.category.displayName]
        if item.foodState != .fresh {
            parts.insert(item.foodState.displayName, at: 1)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func dateRow(_ title: String, _ date: Date?, fallback: String? = nil) -> some View {
        if let date {
            LabeledContent(title, value: date.formatted(date: .abbreviated, time: .omitted))
        } else if let fallback {
            LabeledContent(title, value: fallback)
        }
    }

    // MARK: - Actions

    // Older items may not have a saved product yet; create one so Buy Again works.
    private func ensureProduct() -> Product {
        if let product = item.product { return product }
        let product = Product(name: item.name, category: item.category)
        modelContext.insert(product)
        item.product = product
        return product
    }

    private func addToShoppingList() {
        shoppingListMessage = ShoppingList.add(ensureProduct(), in: modelContext)
    }
}

#Preview {
    NavigationStack {
        GroceryDetailView(item: SampleData.previewSampleItem)
    }
    .modelContainer(SampleData.previewContainer)
}
