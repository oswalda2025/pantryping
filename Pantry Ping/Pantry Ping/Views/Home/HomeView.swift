//
//  HomeView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

// The main screen. Answers one question at a glance: "What should I use next?"
struct HomeView: View {
    // @Query fetches groceries from SwiftData and refreshes automatically when they change.
    // Only items still in the kitchen belong here; used/thrown-away items live in History.
    // (The string literal matches ItemStatus.active.rawValue — #Predicate can't call enum code.)
    @Query(filter: #Predicate<GroceryItem> { $0.statusRaw == "active" })
    private var groceries: [GroceryItem]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.now) private var now

    // nil means "All locations".
    @State private var locationFilter: StorageLocation?
    @State private var searchText = ""
    @State private var isShowingAddForm = false
    @State private var isShowingSettings = false
    @State private var isShowingProducts = false
    // Setting one of these to an item presents a sheet for it.
    @State private var itemToRedate: GroceryItem?
    @State private var itemToUse: GroceryItem?

    var body: some View {
        // NavigationStack enables pushing to a detail screen and shows the title bar.
        NavigationStack {
            List {
                if !groceries.isEmpty {
                    PantrySummary(groceries: groceries, now: now)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

                    locationPicker
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }

                ForEach(sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            NavigationLink(value: item) {
                                GroceryRow(item: item)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Use Some", systemImage: "minus.circle") {
                                    itemToUse = item
                                }
                                .tint(.blue)
                                Button("Finished", systemImage: "checkmark") {
                                    resolve(item, as: .used)
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Threw Away", systemImage: "trash") {
                                    resolve(item, as: .discarded)
                                }
                                .tint(.red)
                                if item.expirationStatus(now: now) == .expired {
                                    Button(item.isPastDateRisky ? "Update Date" : "Still Have It",
                                           systemImage: "arrow.uturn.backward") {
                                        itemToRedate = item
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pantry Ping")
            .searchable(text: $searchText, prompt: "Search groceries")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("Saved Products", systemImage: "square.grid.2x2") { isShowingProducts = true }
                        Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Grocery", systemImage: "plus") {
                        isShowingAddForm = true
                    }
                }
            }
            // Tells the NavigationStack which screen to show for a tapped GroceryItem.
            .navigationDestination(for: GroceryItem.self) { item in
                GroceryDetailView(item: item)
            }
            .sheet(isPresented: $isShowingAddForm) {
                AddGroceryView()
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingProducts) {
                ProductCatalogView()
            }
            .sheet(item: $itemToUse) { item in
                UseSomeSheet(package: item)
            }
            // `item:` presents the sheet whenever the optional becomes non-nil.
            .sheet(item: $itemToRedate) { item in
                UseByDateSheet(item: item, newState: nil)
            }
            .overlay {
                emptyState
            }
            .animation(.default, value: groceries.count)
        }
    }

    // MARK: - Sections

    // The filtered groceries, grouped into urgency sections, most urgent first.
    private var sections: [(title: String, items: [GroceryItem])] {
        let visible = GroceryItem.sortedByUrgency(
            groceries.filter(matchesFilters),
            now: now
        )
        let groups: [(title: String, statuses: [ExpirationStatus])] = [
            ("Expired", [.expired]),
            ("Needs Attention", [.urgent]),
            ("Use Soon", [.useSoon]),
            ("Your Food", [.fresh, .noDate]),
        ]
        // compactMap transforms each group and drops the nil (empty) ones.
        return groups.compactMap { group in
            let items = visible.filter { group.statuses.contains($0.expirationStatus(now: now)) }
            return items.isEmpty ? nil : (group.title, items)
        }
    }

    private func matchesFilters(_ item: GroceryItem) -> Bool {
        let matchesLocation = locationFilter == nil || item.storageLocation == locationFilter
        let matchesSearch = searchText.isEmpty || item.displayName.localizedStandardContains(searchText)
        return matchesLocation && matchesSearch
    }

    private var locationPicker: some View {
        Picker("Location", selection: $locationFilter) {
            Text("All").tag(StorageLocation?.none)
            ForEach(StorageLocation.allCases) { location in
                Text(location.displayName).tag(Optional(location))
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyState: some View {
        if groceries.isEmpty {
            ContentUnavailableView {
                Label("Your kitchen is empty", systemImage: "refrigerator")
            } description: {
                Text("Add what you bought and Pantry Ping will tell you what to use first.")
            } actions: {
                Button("Add Grocery") { isShowingAddForm = true }
                    .buttonStyle(.borderedProminent)
                Button("Try Sample Groceries") {
                    SampleData.insertSampleGroceries(into: modelContext, now: now)
                }
            }
        } else if sections.isEmpty {
            if searchText.isEmpty {
                ContentUnavailableView(
                    "Nothing in the \(locationFilter?.displayName ?? "kitchen")",
                    systemImage: "tray",
                    description: Text("Items you store here will show up in this list.")
                )
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    // MARK: - Actions

    private func resolve(_ item: GroceryItem, as status: ItemStatus) {
        withAnimation {
            if status == .used {
                item.finish()
            } else {
                item.throwAway()
            }
        }
    }
}

// The friendly header: greeting plus a one-line pantry status.
private struct PantrySummary: View {
    let groceries: [GroceryItem]
    let now: Date
    @AppStorage(ProfileKeys.name) private var name = ""

    var body: some View {
        let statuses = groceries.map { $0.expirationStatus(now: now) }
        let expiredCount = statuses.filter { $0 == .expired }.count
        let urgentCount = statuses.filter { $0 == .urgent }.count

        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.title3.weight(.semibold))
            Label(summary(expired: expiredCount, urgent: urgentCount),
                  systemImage: expiredCount + urgentCount > 0 ? "bell.badge" : "checkmark.seal")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // "Good evening, Dhiren" — or just "Good evening" when no name was given.
    private var greeting: String {
        let timeOfDay = switch Calendar.current.component(.hour, from: now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? timeOfDay : "\(timeOfDay), \(trimmed)"
    }

    private func summary(expired: Int, urgent: Int) -> String {
        switch (expired, urgent) {
        case (0, 0):
            return "Nothing urgent — \(groceries.count) \(groceries.count == 1 ? "item" : "items") in your kitchen."
        case (0, _):
            return "\(urgent) \(urgent == 1 ? "item needs" : "items need") attention — use today or tomorrow."
        case (_, 0):
            return "\(expired) \(expired == 1 ? "item is" : "items are") past \(expired == 1 ? "its" : "their") date."
        default:
            // Matches the section names below: "Needs Attention" and "Expired".
            return "\(urgent) \(urgent == 1 ? "needs" : "need") attention · \(expired) past date."
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(SampleData.previewContainer)
}
