//
//  MealsView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

// Prepared meals: batches you've cooked, with their portions and dates.
struct MealsView: View {
    @Query(sort: \PreparedMeal.preparedDate, order: .reverse) private var meals: [PreparedMeal]
    @Environment(\.now) private var now
    @State private var isCreatingMeal = false
    @State private var mealToEat: PreparedMeal?

    // Active meals, soonest date first (undated last).
    private var activeMeals: [PreparedMeal] {
        meals.filter { $0.status == .active }.sorted { first, second in
            switch (first.daysRemaining(now: now), second.daysRemaining(now: now)) {
            case let (a?, b?): a < b
            case (.some, .none): true
            case (.none, .some): false
            default: first.preparedDate > second.preparedDate
            }
        }
    }

    private var pastMeals: [PreparedMeal] {
        meals.filter { $0.status != .active }
    }

    var body: some View {
        NavigationStack {
            List {
                if !activeMeals.isEmpty {
                    Section("In Your Kitchen") {
                        ForEach(activeMeals) { meal in
                            NavigationLink(value: meal) {
                                MealRow(meal: meal)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Eat", systemImage: "fork.knife") { mealToEat = meal }
                                    .tint(.blue)
                            }
                        }
                    }
                }
                if !pastMeals.isEmpty {
                    Section("Past Meals") {
                        ForEach(pastMeals) { meal in
                            NavigationLink(value: meal) {
                                MealRow(meal: meal)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Meals")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Meal Prep", systemImage: "plus") { isCreatingMeal = true }
                }
            }
            .navigationDestination(for: PreparedMeal.self) { meal in
                MealDetailView(meal: meal)
            }
            .sheet(isPresented: $isCreatingMeal) {
                MealFormView()
            }
            .sheet(item: $mealToEat) { meal in
                EatPortionSheet(meal: meal)
            }
            .overlay {
                if meals.isEmpty {
                    ContentUnavailableView {
                        Label("No prepared meals", systemImage: "takeoutbag.and.cup.and.straw")
                    } description: {
                        Text("Record a meal-prep batch from groceries in your kitchen, or enter a meal by hand.")
                    } actions: {
                        Button("New Meal Prep") { isCreatingMeal = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}

struct MealRow: View {
    let meal: PreparedMeal
    @Environment(\.now) private var now

    var body: some View {
        let status = meal.expirationStatus(now: now)
        HStack(spacing: 12) {
            Image(systemName: meal.status == .active ? status.systemImage : "checkmark.circle")
                .font(.title3)
                .foregroundStyle(meal.status == .active ? status.tint : .secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.body.weight(.medium))
                Text(meal.status == .active
                     ? "\(meal.storageLocation.displayName) · \(meal.remainingText) left"
                     : meal.status.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if meal.status == .active {
                Text(meal.freshnessText(now: now))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(status == .expired ? .red : status == .urgent ? .orange : .secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// One prepared meal: what's left, nutrition, ingredients, and actions.
struct MealDetailView: View {
    let meal: PreparedMeal

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.now) private var now
    @State private var isEating = false
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var deleteWhenClosed = false

    var body: some View {
        if meal.isDeleted || meal.modelContext == nil {
            ContentUnavailableView("Meal deleted", systemImage: "trash")
        } else {
            content
        }
    }

    private var content: some View {
        let status = meal.expirationStatus(now: now)
        return List {
            Section {
                Label {
                    Text(meal.freshnessText(now: now)).foregroundStyle(status.textColor)
                } icon: {
                    Image(systemName: status.systemImage).foregroundStyle(status.tint)
                }
                .font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(meal.remainingText) left")
                        .font(.headline)
                    ProgressView(value: Double(meal.remainingAmountMilli), total: Double(max(meal.startingAmountMilli, 1)))
                        .accessibilityHidden(true)
                    Text("of \(meal.amountText(milli: meal.startingAmountMilli))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                if meal.expirationSource == .suggested, meal.expirationDate != nil {
                    HStack(alignment: .top) {
                        SuggestedTag()
                        Text(StorageGuidance.caveat).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if meal.status == .active {
                Section {
                    Button("Eat a Portion", systemImage: "fork.knife") { isEating = true }
                    Button("Finished", systemImage: "checkmark.circle") {
                        meal.status = .used
                        dismiss()
                    }
                    .tint(.green)
                    Button("Threw Away", systemImage: "trash") {
                        meal.status = .discarded
                        dismiss()
                    }
                    .tint(.red)
                }
            } else {
                Section {
                    LabeledContent(meal.status.displayName,
                                   value: meal.dateResolved?.formatted(date: .abbreviated, time: .omitted) ?? "")
                    if meal.canRestoreToKitchen {
                        Button("Move Back to Kitchen", systemImage: "arrow.uturn.backward") { meal.status = .active }
                    }
                }
            }

            nutritionSection

            if let ingredients = meal.ingredients, !ingredients.isEmpty {
                Section("Ingredients") {
                    ForEach(ingredients.sorted { $0.name < $1.name }) { ingredient in
                        LabeledContent {
                            Text(ingredient.amountText)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(ingredient.name)
                                Text(ingredient.fromInventory ? "From your kitchen" : "Not tracked")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Details") {
                LabeledContent("Prepared", value: meal.preparedDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Stored in", value: meal.storageLocation.displayName)
                LabeledContent {
                    HStack {
                        if meal.expirationSource == .suggested && meal.expirationDate != nil { SuggestedTag() }
                        Text(meal.expirationDate?.formatted(date: .abbreviated, time: .omitted) ?? "No date")
                    }
                } label: {
                    Text("Use by")
                }
                if let portions = meal.totalPortions {
                    LabeledContent("Portions made", value: Quantity.number(portions, maxFractionDigits: 2))
                }
                if let weight = meal.totalWeightGrams {
                    LabeledContent("Cooked weight", value: Quantity.text(weight, unit: .gram))
                }
                if !meal.notes.isEmpty {
                    LabeledContent("Notes", value: meal.notes)
                }
            }

            Section {
                Button("Delete Meal", role: .destructive) { isConfirmingDelete = true }
            } footer: {
                Text("Deleting doesn't put ingredients back or remove what you've logged eating.")
            }
        }
        .navigationTitle(meal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { isEditing = true }
        }
        .sheet(isPresented: $isEating) {
            EatPortionSheet(meal: meal)
        }
        .sheet(isPresented: $isEditing) {
            EditMealView(meal: meal)
        }
        .confirmationDialog("Delete \(meal.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteWhenClosed = true
                dismiss()
            }
        }
        .onDisappear {
            if deleteWhenClosed { modelContext.delete(meal) }
        }
    }

    private var nutritionSection: some View {
        Section {
            if meal.batchNutrition.isEmpty {
                Text("Not entered")
                    .foregroundStyle(.secondary)
            } else {
                if let perPortion = meal.perPortionNutrition {
                    nutritionRow("Per portion", perPortion)
                }
                if let per100g = meal.per100gNutrition {
                    nutritionRow("Per 100 g", per100g)
                }
                nutritionRow("Whole batch", meal.batchNutrition)
            }
        } header: {
            Text("Nutrition")
        } footer: {
            Text(nutritionNote)
        }
    }

    private func nutritionRow(_ title: String, _ facts: NutritionFacts) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.medium))
            Text(NutritionFormat.summary(facts) ?? "Not entered")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if facts.calories == nil || facts.carbs == nil || facts.protein == nil || facts.fat == nil {
                Text("Some values not entered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var nutritionNote: String {
        switch meal.nutritionSource {
        case .manual:
            return "Entered by hand."
        case .calculated:
            let missing = meal.ingredientsMissingCalories
            return missing == 0
                ? "Calculated from ingredients."
                : "Calculated from ingredients. \(missing) ingredient\(missing == 1 ? " has" : "s have") no calories entered, so calories aren't shown."
        case .none:
            let count = meal.ingredients?.count ?? 0
            return count == 0
                ? "Add nutrition by editing the meal, if you want to track it."
                : "Not enough ingredient nutrition to calculate this."
        }
    }
}

// Edits where a meal is stored and its use-by date (with the fridge suggestion).
struct EditMealView: View {
    let meal: PreparedMeal
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var storage: StorageLocation
    @State private var hasUseByDate: Bool
    @State private var useByDate: Date
    @State private var source: ExpirationSource
    @State private var notes: String

    init(meal: PreparedMeal) {
        self.meal = meal
        _name = State(initialValue: meal.name)
        _storage = State(initialValue: meal.storageLocation)
        _hasUseByDate = State(initialValue: meal.expirationDate != nil)
        _useByDate = State(initialValue: meal.expirationDate ?? .now)
        _source = State(initialValue: meal.expirationSource)
        _notes = State(initialValue: meal.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                }
                MealStorageFields(storage: $storage, preparedDate: meal.preparedDate,
                                  hasUseByDate: $hasUseByDate, useByDate: $useByDate, source: $source)
                Section {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(1...4)
                }
            }
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { meal.name = trimmed }
                        meal.storageLocation = storage
                        meal.expirationDate = hasUseByDate ? CalendarDay.noon(useByDate) : nil
                        meal.expirationSource = hasUseByDate ? source : .entered
                        meal.notes = notes
                        dismiss()
                    }
                }
            }
        }
    }
}

// Storage + use-by fields shared by the new-meal and edit-meal forms, including the
// "Use suggestion" option for refrigerated meals.
struct MealStorageFields: View {
    @Binding var storage: StorageLocation
    let preparedDate: Date
    @Binding var hasUseByDate: Bool
    @Binding var useByDate: Date
    @Binding var source: ExpirationSource
    // The exact day that was filled in from the suggestion. A date only stays "suggested"
    // while it's still exactly this day.
    @State private var appliedSuggestionDate: Date?

    init(storage: Binding<StorageLocation>, preparedDate: Date, hasUseByDate: Binding<Bool>,
         useByDate: Binding<Date>, source: Binding<ExpirationSource>) {
        _storage = storage
        self.preparedDate = preparedDate
        _hasUseByDate = hasUseByDate
        _useByDate = useByDate
        _source = source
        _appliedSuggestionDate = State(initialValue: source.wrappedValue == .suggested ? useByDate.wrappedValue : nil)
    }

    private var suggestion: StorageSuggestion? {
        StorageGuidance.suggestion(forPreparedMealIn: storage)
    }

    var body: some View {
        Section("Stored In") {
            Picker("Stored In", selection: $storage) {
                ForEach(StorageLocation.allCases) { location in
                    Text(location.displayName).tag(location)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if storage == .freezer {
                Text(StorageGuidance.freezerNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        if let suggestion {
            Section {
                Text(suggestion.message).font(.callout)
                Button("Use Suggestion: \(suggestion.date(from: preparedDate).formatted(date: .abbreviated, time: .omitted))") {
                    applySuggestion()
                }
            } header: {
                Text("General Guidance · \(suggestion.source)")
            } footer: {
                Text(StorageGuidance.caveat)
            }
        }

        Section("Use By") {
            Toggle("Use-by date", isOn: $hasUseByDate.animation())
            if hasUseByDate {
                HStack {
                    DatePicker("Date", selection: $useByDate, displayedComponents: .date)
                    if source == .suggested { SuggestedTag() }
                }
            }
        }
        // Editing a suggested date by hand makes it the user's own date.
        .onChange(of: useByDate) { _, newDate in
            if source == .suggested,
               !(appliedSuggestionDate.map { Calendar.current.isDate(newDate, inSameDayAs: $0) } ?? false) {
                source = .entered
                appliedSuggestionDate = nil
            }
        }
        // A suggestion depends on where the meal is stored and when it was made. If either
        // changes, recompute it — or remove it when the new storage has no general rule.
        .onChange(of: storage) { _, _ in refreshSuggestion() }
        .onChange(of: preparedDate) { _, _ in refreshSuggestion() }
    }

    private func applySuggestion() {
        guard let suggestion else { return }
        let date = suggestion.date(from: preparedDate)
        appliedSuggestionDate = date
        source = .suggested
        withAnimation {
            useByDate = date
            hasUseByDate = true
        }
    }

    private func refreshSuggestion() {
        guard source == .suggested else { return }
        if suggestion != nil {
            applySuggestion()
        } else {
            appliedSuggestionDate = nil
            source = .entered
            withAnimation { hasUseByDate = false }
        }
    }
}
