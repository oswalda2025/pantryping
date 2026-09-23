//
//  HistoryView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

// Items that have left the kitchen — used or thrown away. Kept (not deleted) so mistakes
// can be undone and future food-waste stats have data to work with.
struct HistoryView: View {
    @Query(filter: #Predicate<GroceryItem> { $0.statusRaw != "active" })
    private var resolvedItems: [GroceryItem]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.now) private var now

    // Most recently resolved first.
    private var sortedItems: [GroceryItem] {
        resolvedItems.sorted { ($0.dateResolved ?? .distantPast) > ($1.dateResolved ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !resolvedItems.isEmpty {
                    Section {
                        let usedCount = resolvedItems.filter { $0.status == .used }.count
                        let tossedCount = resolvedItems.count - usedCount
                        HStack {
                            countTile(usedCount, label: "Used", systemImage: "checkmark.circle.fill", tint: .green)
                            countTile(tossedCount, label: "Thrown Away", systemImage: "trash.fill", tint: .red)
                        }
                    }
                }

                Section {
                    ForEach(sortedItems) { item in
                        NavigationLink(value: item) {
                            HistoryRow(item: item, now: now)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Restore", systemImage: "arrow.uturn.backward") {
                                withAnimation { item.status = .active }
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                modelContext.delete(item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: GroceryItem.self) { item in
                GroceryDetailView(item: item)
            }
            .overlay {
                if resolvedItems.isEmpty {
                    ContentUnavailableView(
                        "No history yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Groceries you mark as Used or Thrown Away show up here.")
                    )
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
                Text(item.name)
                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // "Used yesterday" / "Thrown away 3 days ago"
    private var detailText: String {
        let verb = item.status == .used ? "Used" : "Thrown away"
        guard let date = item.dateResolved else { return verb }
        return "\(verb) \(GroceryItem.relativeDayText(from: date, now: now))"
    }
}

#Preview {
    HistoryView()
        .modelContainer(SampleData.previewContainer)
}
