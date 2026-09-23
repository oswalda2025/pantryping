//
//  MealFormView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

// Records a meal-prep batch. Ingredients from the kitchen are taken out of their
// packages when it's saved. A meal can also be entered by hand with no ingredients.
struct MealFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var ingredients: [IngredientDraft] = []
    @State private var portionsText = ""
    @State private var weightText = ""
    @State private var preparedDate = Date.now
    @State private var storage = StorageLocation.fridge
    @State private var hasUseByDate = false
    @State private var useByDate = Date.now
    @State private var source = ExpirationSource.entered
    @State private var entersNutritionManually = false
    @State private var manualPerPortion = true
    @State private var caloriesText = ""
    @State private var carbsText = ""
    @State private var proteinText = ""
    @State private var fatText = ""
    @State private var notes = ""
    @State private var isAddingIngredient = false
    @State private var errorMessage: String?

    private var portions: Double? { NumberInput.double(portionsText).flatMap { $0 > 0 ? $0 : nil } }
    private var weight: Double? { NumberInput.double(weightText).flatMap { $0 > 0 ? $0 : nil } }

    // Nutrition added up from the ingredients chosen so far (a live preview).
    private var ingredientTotal: NutritionTotal {
        ingredients.reduce(into: NutritionTotal()) { total, draft in
            if let package = draft.package, let milli = try? package.milli(for: draft.amount, unit: draft.unit) {
                total.add(package.nutrition(forMilli: milli))
            } else {
                total.add(.empty)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Meal name, e.g. Chicken Rice Bowls", text: $name)
                        .textInputAutocapitalization(.sentences)
                }

                ingredientsSection

                Section {
                    NumberField(title: "Portions", text: $portionsText)
                    NumberField(title: "Cooked weight", text: $weightText, suffix: "g")
                } header: {
                    Text("Yield")
                } footer: {
                    Text("Enter the number of portions, the cooked weight, or both. With both, you can log eating by portion or by weight.")
                }

                nutritionSection

                MealStorageFields(storage: $storage, preparedDate: preparedDate,
                                  hasUseByDate: $hasUseByDate, useByDate: $useByDate, source: $source)

                Section {
                    DatePicker("Prepared", selection: $preparedDate, in: ...Date.now, displayedComponents: .date)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(1...4)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("New Meal Prep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $isAddingIngredient) {
                IngredientPickerSheet { draft in ingredients.append(draft) }
            }
        }
    }

    private var ingredientsSection: some View {
        Section {
            ForEach(ingredients) { draft in
                LabeledContent {
                    Text(Quantity.text(draft.amount, unit: draft.unit))
                } label: {
                    VStack(alignment: .leading) {
                        Text(draft.package?.displayName ?? draft.name)
                        Text(draft.package == nil ? "Not tracked" : "From your kitchen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { ingredients.remove(atOffsets: $0) }
            Button("Add Ingredient", systemImage: "plus.circle") { isAddingIngredient = true }
        } header: {
            Text("Ingredients")
        } footer: {
            Text("Optional. Ingredients from your kitchen are taken out of their packages when you save.")
        }
    }

    private var nutritionSection: some View {
        Section {
            if !ingredients.isEmpty && !entersNutritionManually {
                let total = ingredientTotal
                LabeledContent("Batch calories", value: total.calories.text(unit: "kcal", digits: 0))
                if let calories = total.calories.completeValue {
                    if let portions {
                        LabeledContent("Per portion", value: NutritionFormat.calories(calories / portions))
                    }
                    if let weight {
                        LabeledContent("Per 100 g", value: NutritionFormat.calories(calories / weight * 100))
                    }
                }
            }
            Toggle("Enter nutrition by hand", isOn: $entersNutritionManually.animation())
            if entersNutritionManually {
                Picker("Values are", selection: $manualPerPortion) {
                    Text("Per portion").tag(true)
                    Text("Whole batch").tag(false)
                }
                .pickerStyle(.segmented)
                NumberField(title: "Calories", text: $caloriesText, suffix: "kcal")
                NumberField(title: "Carbohydrates", text: $carbsText, suffix: "g")
                NumberField(title: "Protein", text: $proteinText, suffix: "g")
                NumberField(title: "Fat", text: $fatText, suffix: "g")
            }
        } header: {
            Text("Nutrition")
        } footer: {
            Text("Optional. Calculated values only include nutrients every ingredient has; missing values are never counted as zero.")
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var manual: NutritionFacts?
        if entersNutritionManually {
            let entered = NutritionFacts(
                calories: NumberInput.double(caloriesText),
                carbs: NumberInput.double(carbsText),
                protein: NumberInput.double(proteinText),
                fat: NumberInput.double(fatText)
            )
            if manualPerPortion && !entered.isEmpty {
                guard let portions else {
                    errorMessage = "Enter the number of portions to use per-portion nutrition."
                    return
                }
                manual = entered.scaled(by: portions)
            } else {
                manual = entered
            }
        }
        do {
            _ = try MealPrep.makeMeal(
                name: trimmed,
                ingredients: ingredients,
                yield: .init(portions: portions, cookedWeightGrams: weight),
                preparedDate: preparedDate,
                storageLocation: storage,
                expirationDate: hasUseByDate ? useByDate : nil,
                expirationSource: source,
                manualBatchNutrition: manual,
                notes: notes,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// Picks one ingredient: a package from the kitchen (soonest-expiring first) with an
// amount, or something not tracked in the kitchen.
struct IngredientPickerSheet: View {
    let onAdd: (IngredientDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.now) private var now
    @Query(filter: #Predicate<GroceryItem> { $0.statusRaw == "active" }) private var packages: [GroceryItem]

    @State private var fromKitchen = true
    @State private var selected: GroceryItem?
    @State private var amountText = ""
    @State private var unit = MeasureUnit.serving
    @State private var otherName = ""

    private var sortedPackages: [GroceryItem] {
        GroceryItem.sortedByUrgency(packages, now: now)
    }

    private var units: [MeasureUnit] {
        if fromKitchen, let selected { return selected.converter.enterableUnits }
        return [.serving, .piece] + MeasureUnit.labelUnits.filter { $0 != .piece }
    }

    // A message about the amount, or nil when it's fine.
    private var amountProblem: String? {
        guard let amount = NumberInput.double(amountText), amount > 0 else { return "Enter an amount." }
        guard fromKitchen, let selected else { return nil }
        do {
            let milli = try selected.milli(for: amount, unit: unit)
            return milli > selected.remainingAmountMilli ? "Only \(selected.remainingText) left." : nil
        } catch {
            return error.localizedDescription
        }
    }

    private var canAdd: Bool {
        amountProblem == nil && (fromKitchen ? selected != nil : !otherName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Source", selection: $fromKitchen) {
                    Text("From Kitchen").tag(true)
                    Text("Other").tag(false)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if fromKitchen {
                    Section {
                        if sortedPackages.isEmpty {
                            Text("Nothing in your kitchen yet.").foregroundStyle(.secondary)
                        }
                        ForEach(sortedPackages) { package in
                            Button {
                                selected = package
                                if !package.converter.enterableUnits.contains(unit) {
                                    unit = package.converter.enterableUnits.first ?? package.quantityUnit
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(package.displayName).foregroundStyle(.primary)
                                        Text("\(package.remainingText) · \(package.freshnessText(now: now))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selected == package {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Use Soonest First")
                    }
                } else {
                    Section {
                        TextField("Ingredient, e.g. Lemon", text: $otherName)
                    } footer: {
                        Text("Not taken from your kitchen and has no nutrition, so meal totals will be marked incomplete.")
                    }
                }

                Section {
                    HStack {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Amount")
                        Picker("Unit", selection: $unit) {
                            ForEach(units) { unit in
                                Text(unit.label(for: 2)).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                } header: {
                    Text("Amount")
                } footer: {
                    if !amountText.isEmpty, let amountProblem {
                        Text(amountProblem).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let amount = NumberInput.double(amountText) else { return }
                        let draft = IngredientDraft(
                            name: fromKitchen ? (selected?.displayName ?? "") : otherName.trimmingCharacters(in: .whitespaces),
                            package: fromKitchen ? selected : nil,
                            amount: amount,
                            unit: unit
                        )
                        onAdd(draft)
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
            .onChange(of: fromKitchen) { _, isKitchen in
                if !units.contains(unit) { unit = units.first ?? .serving }
                if !isKitchen { selected = nil }
            }
        }
    }
}
