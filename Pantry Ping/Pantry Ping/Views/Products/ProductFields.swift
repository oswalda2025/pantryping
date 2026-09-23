//
//  ProductFields.swift
//  Pantry Ping
//

import SwiftUI

// The editable details of a saved product, held as text while the form is open.
// Only the name is required; blank numbers are saved as "not entered" (nil), never 0.
struct ProductDraft {
    var name = ""
    var category = GroceryCategory.other
    var photoData: Data?
    var servingSizeText = ""
    var servingUnit = MeasureUnit.gram
    var servingsPerPackageText = ""
    var caloriesText = ""
    var carbsText = ""
    var proteinText = ""
    var fatText = ""

    init(name: String = "") {
        self.name = name
    }

    init(product: Product) {
        name = product.name
        category = product.category
        photoData = product.photoData
        servingSizeText = NumberInput.text(product.servingSize)
        servingUnit = product.servingUnit ?? .gram
        servingsPerPackageText = NumberInput.text(product.servingsPerPackage)
        caloriesText = NumberInput.text(product.calories)
        carbsText = NumberInput.text(product.carbs)
        proteinText = NumberInput.text(product.protein)
        fatText = NumberInput.text(product.fat)
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var servingSize: Double? { positive(servingSizeText) }
    var servingsPerPackage: Double? { positive(servingsPerPackageText) }

    var nutrition: NutritionFacts {
        NutritionFacts(
            calories: NumberInput.double(caloriesText),
            carbs: NumberInput.double(carbsText),
            protein: NumberInput.double(proteinText),
            fat: NumberInput.double(fatText)
        )
    }

    var hasServingOrNutrition: Bool {
        !servingSizeText.isEmpty || !servingsPerPackageText.isEmpty || !nutrition.isEmpty
    }

    // A message explaining what's wrong, or nil when the draft can be saved.
    var problem: String? {
        if trimmedName.isEmpty { return "Enter a name." }
        let numbers = [servingSizeText, servingsPerPackageText, caloriesText, carbsText, proteinText, fatText]
        for text in numbers where !text.isEmpty {
            guard let value = NumberInput.double(text) else { return "“\(text)” isn't a number." }
            if value < 0 { return "Numbers can't be negative." }
        }
        return nil
    }

    func apply(to product: Product) {
        product.name = trimmedName
        product.category = category
        product.photoData = photoData
        product.servingSize = servingSize
        product.servingUnit = servingSize == nil ? nil : servingUnit
        product.servingsPerPackage = servingsPerPackage
        product.nutrition = nutrition
        // Keep each package's copy of the name in sync.
        for package in product.packages ?? [] {
            package.name = product.name
            package.category = product.category
        }
    }

    private func positive(_ text: String) -> Double? {
        guard let value = NumberInput.double(text), value > 0 else { return nil }
        return value
    }
}

// Form sections for a product: name, photo, category, serving, and nutrition.
struct ProductFields: View {
    @Binding var draft: ProductDraft
    @State private var isShowingNutrition: Bool

    init(draft: Binding<ProductDraft>) {
        _draft = draft
        // Start expanded when editing a product that already has values.
        _isShowingNutrition = State(initialValue: draft.wrappedValue.hasServingOrNutrition)
    }

    var body: some View {
        Section {
            TextField("Product name, e.g. Protein Granola", text: $draft.name)
                .textInputAutocapitalization(.words)
            Picker("Category", selection: $draft.category) {
                ForEach(GroceryCategory.allCases) { category in
                    Text(category.displayName).tag(category)
                }
            }
            ProductPhotoPicker(photoData: $draft.photoData)
        } header: {
            Text("Product")
        } footer: {
            Text("The photo is saved with the product, so buying it again reuses it.")
        }

        Section {
            DisclosureGroup("Serving & Nutrition", isExpanded: $isShowingNutrition) {
                HStack {
                    Text("Serving size")
                    Spacer()
                    TextField("Optional", text: $draft.servingSizeText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                        .accessibilityLabel("Serving size")
                    Picker("Serving unit", selection: $draft.servingUnit) {
                        ForEach(MeasureUnit.labelUnits) { unit in
                            Text(unit.label(for: 2)).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                NumberField(title: "Servings per package", text: $draft.servingsPerPackageText)
                NumberField(title: "Calories", text: $draft.caloriesText, suffix: "kcal")
                NumberField(title: "Carbohydrates", text: $draft.carbsText, suffix: "g")
                NumberField(title: "Protein", text: $draft.proteinText, suffix: "g")
                NumberField(title: "Fat", text: $draft.fatText, suffix: "g")
            }
        } footer: {
            Text("All optional, per serving, from the label. The serving size lets Pantry Ping convert between servings and grams. Blanks show as “not entered”, never as zero.")
        }
    }
}
