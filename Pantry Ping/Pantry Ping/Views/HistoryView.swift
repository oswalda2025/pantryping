//
//  HistoryView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

// Two views of the past:
// - Purchases: everything bought, grouped by day, with package sizes and costs.
// - Finished: packages that left the kitchen (finished or thrown away), kept for history.
struct HistoryView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case purchases = "Purchases"
        case finished = "Finished"
        var id: String { rawValue }
    }

    @Query(sort: \GroceryItem.purchaseDate, order: .reverse) private var allPackages: [GroceryItem]
    @Query(filter: #Predicate<GroceryItem> { $0.statusRaw != "active" })
    private var resolvedItems: [GroceryItem]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.now) private var now

    @State private var mode = Mode.purchases
    // The item waiting for delete confirmation (deleting is permanent).
    @State private var itemToDelete: GroceryItem?

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                switch mode {
                case .purchases: purchaseSections
                case .finished: finishedSections
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: GroceryItem.self) { item in
                GroceryDetailView(item: item)
            }
            .confirmationDialog(
                "Delete \(itemToDelete?.displayName ?? "item") permanently?",
                isPresented: Binding(
                    get: { itemToDelete != nil },
                    set: { if !$0 { itemToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: itemToDelete
            ) { item in
                Button("Delete", role: .destructive) {
                    withAnimation { modelContext.delete(item) }
                }
            } message: { _ in
                Text("It will no longer count in your history.")
            }
            .overlay { emptyState }
        }
    }

    // MARK: - Purchases

    // Packages grouped by the day they were bought, newest day first.
    private var purchaseDays: [(day: Date, packages: [GroceryItem])] {
        let groups = Dictionary(grouping: allPackages) { Calendar.current.startOfDay(for: $0.purchaseDate) }
        return groups.keys.sorted(by: >).map { day in (day, groups[day] ?? []) }
    }

    @ViewBuilder
    private var purchaseSections: some View {
        ForEach(purchaseDays, id: \.day) { group in
            Section {
                ForEach(group.packages) { package in
                    NavigationLink(value: package) {
                        PurchaseRow(package: package)
                    }
                }
            } header: {
                Text(dayTitle(group.day))
            } footer: {
                Text(costSummary(group.packages))
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day.formatted(date: .complete, time: .omitted)
    }

    // "Total $12.49", noting items bought without a price so the total isn't misleading.
    private func costSummary(_ packages: [GroceryItem]) -> String {
        let prices = packages.compactMap(\.price)
        let missing = packages.count - prices.count
        guard !prices.isEmpty else { return "No prices entered" }
        let total = prices.reduce(Decimal(0), +).formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
        return missing == 0 ? "Total \(total)" : "Total \(total) · \(missing) without a price"
    }

    // MARK: - Finished

    private var sortedResolved: [GroceryItem] {
        resolvedItems.sorted { ($0.dateResolved ?? .distantPast) > ($1.dateResolved ?? .distantPast) }
    }

    @ViewBuilder
    private var finishedSections: some View {
        if !resolvedItems.isEmpty {
            Section {
                let finishedCount = resolvedItems.filter { $0.status == .used }.count
                HStack {
                    countTile(finishedCount, label: "Finished", systemImage: "checkmark.circle.fill", tint: .green)
                    countTile(resolvedItems.count - finishedCount, label: "Thrown Away", systemImage: "trash.fill", tint: .red)
                }
            }
        }
        Section {
            ForEach(sortedResolved) { item in
                NavigationLink(value: item) {
                    HistoryRow(item: item, now: now)
                }
                .swipeActions(edge: .leading) {
                    if item.canRestoreToKitchen {
                        Button("Restore", systemImage: "arrow.uturn.backward") {
                            withAnimation { item.restoreToKitchen() }
                        }
                        .tint(.blue)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash") {
                        itemToDelete = item
                    }
                    .tint(.red)
                }
            }
        }
    }

    private func countTile(_ count: Int, label: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
            Text("\(count)")
                .font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyState: some View {
        switch mode {
        case .purchases where allPackages.isEmpty:
            ContentUnavailableView("No purchases yet", systemImage: "bag",
                                   description: Text("Groceries you add show up here, grouped by the day you bought them."))
        case .finished where resolvedItems.isEmpty:
            ContentUnavailableView("Nothing finished yet", systemImage: "clock.arrow.circlepath",
                                   description: Text("Groceries you mark Finished or Threw Away show up here."))
        default:
            EmptyView()
        }
    }
}

// One purchase: name, package size, and price.
private struct PurchaseRow: View {
    let package: GroceryItem

    var body: some View {
        HStack(spacing: 12) {
            ProductThumbnail(data: package.product?.photoData, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(package.displayName)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let price = package.price {
                Text(price.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                    .font(.subheadline.monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if package.hasMeaningfulAmount { parts.append(package.startingText) }
        parts.append(package.status == .active ? package.storageLocation.displayName : package.status.displayName)
        return parts.joined(separator: " · ")
    }
}

private struct HistoryRow: View {
    let item: GroceryItem
    let now: Date

    var body: some View {
        HStack {
            Image(systemName: item.status == .used ? "checkmark.circle.fill" : "trash.circle.fill")
                .foregroundStyle(item.status == .used ? .green : .red)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // "Finished yesterday" / "Thrown away 3 days ago"
    private var detailText: String {
        let verb = item.status == .used ? "Finished" : "Thrown away"
        guard let date = item.dateResolved else { return verb }
        return "\(verb) \(GroceryItem.relativeDayText(from: date, now: now))"
    }
}

#Preview {
    HistoryView()
        .modelContainer(SampleData.previewContainer)
}
