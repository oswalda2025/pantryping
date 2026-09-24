//
//  FoodLogView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

// The personal daily food log. Only usage marked "Ate" appears here — food used in
// meal prep or for other things never counts toward what you ate.
struct FoodLogView: View {
    // The string matches UsageReason.ate.rawValue (#Predicate can't call enum code).
    @Query(filter: #Predicate<UsageEntry> { $0.reasonRaw == "ate" }, sort: \UsageEntry.date, order: .reverse)
    private var eaten: [UsageEntry]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.now) private var now
    @State private var day = Date.now

    private var entries: [UsageEntry] {
        eaten.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    // `reduce(into:)` walks the array, updating one running value as it goes.
    private var total: NutritionTotal {
        entries.reduce(into: NutritionTotal()) { total, entry in
            total.add(entry.nutrition)
        }
    }

    private var isToday: Bool {
        Calendar.current.isDate(day, inSameDayAs: now)
    }

    var body: some View {
        // Worked out once per redraw instead of once for every place that shows them.
        let entries = self.entries
        let total = self.total
        return NavigationStack {
            List {
                Section {
                    daySwitcher
                }

                if !entries.isEmpty {
                    Section {
                        LabeledContent("Calories", value: total.calories.text(unit: "kcal", digits: 0))
                        LabeledContent("Carbohydrates", value: total.carbs.text(unit: "g", digits: 1))
                        LabeledContent("Protein", value: total.protein.text(unit: "g", digits: 1))
                        LabeledContent("Fat", value: total.fat.text(unit: "g", digits: 1))
                    } header: {
                        Text("Total")
                    } footer: {
                        if total.calories.missing + total.carbs.missing + total.protein.missing + total.fat.missing > 0 {
                            Text("A “+” means some foods don't have that value entered, so the real total is higher.")
                        }
                    }

                    Section {
                        ForEach(entries) { entry in
                            LogRow(entry: entry)
                                .swipeActions {
                                    Button("Undo", systemImage: "arrow.uturn.backward", role: .destructive) {
                                        withAnimation { entry.undo(in: modelContext) }
                                    }
                                }
                        }
                    } header: {
                        Text("Eaten")
                    } footer: {
                        Text("Swipe left to undo an entry. The amount goes back to its package or meal, if it still exists.")
                    }
                }
            }
            .navigationTitle("Food Log")
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(
                        isToday ? "Nothing logged today" : "Nothing logged",
                        systemImage: "fork.knife",
                        description: Text("When you use some food or eat a portion and choose “Ate”, it shows up here.")
                    )
                }
            }
            .onChange(of: now) { oldNow, newNow in
                // Follow the calendar forward if the log was showing "today".
                if Calendar.current.isDate(day, inSameDayAs: oldNow) { day = newNow }
            }
        }
    }

    private var daySwitcher: some View {
        HStack {
            Button("Previous Day", systemImage: "chevron.left") {
                day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
            }
            .labelStyle(.iconOnly)
            Spacer()
            Text(dayTitle)
                .font(.headline)
            Spacer()
            Button("Next Day", systemImage: "chevron.right") {
                day = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
            }
            .labelStyle(.iconOnly)
            .disabled(isToday)
        }
        .buttonStyle(.borderless)
    }

    private var dayTitle: String {
        if isToday { return "Today" }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now),
           Calendar.current.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct LogRow: View {
    let entry: UsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.itemName)
                    .font(.body.weight(.medium))
                Spacer()
                Text(entry.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(entry.amountText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(NutritionFormat.summary(entry.nutrition) ?? "Nutrition not entered")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
