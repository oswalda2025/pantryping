//
//  UseSomeSheet.swift
//  Pantry Ping
//

import SwiftUI

// Takes an amount out of a package: as servings or as a measured amount (g, oz, ...).
// When the product has several open packages, the one expiring first is suggested,
// but the user can pick any of them.
struct UseSomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.now) private var now

    @State private var package: GroceryItem
    @State private var amountText = ""
    @State private var unit: MeasureUnit
    @State private var reason = UsageReason.ate
    @State private var date = Date.now
    // "Use all" takes exactly what's left, avoiding any rounding from unit conversion.
    @State private var usesEverything = false
    @State private var errorMessage: String?

    init(package: GroceryItem) {
        _package = State(initialValue: package)
        _unit = State(initialValue: package.converter.enterableUnits.first ?? package.quantityUnit)
    }

    // Other open packages of the same product, the one that expires first at the top.
    private var candidates: [GroceryItem] {
        let others = package.product?.activePackagesByExpiry ?? []
        return others.isEmpty ? [package] : others
    }

    private var suggestedPackage: GroceryItem? {
        candidates.count > 1 ? candidates.first : nil
    }

    // The amount in the package's stored unit, or an error explaining the problem.
    private var parsedMilli: Result<Int, InventoryError> {
        if usesEverything { return .success(package.remainingAmountMilli) }
        guard let value = NumberInput.double(amountText) else { return .failure(.invalidAmount) }
        do {
            let milli = try package.milli(for: value, unit: unit)
            guard milli <= package.remainingAmountMilli else {
                return .failure(.notEnoughLeft(available: package.remainingText))
            }
            return .success(milli)
        } catch let error as InventoryError {
            return .failure(error)
        } catch {
            return .failure(.invalidAmount)
        }
    }

    private var validMilli: Int? {
        if case .success(let milli) = parsedMilli { return milli }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if candidates.count > 1 {
                    Section {
                        Picker("Package", selection: $package) {
                            ForEach(candidates) { candidate in
                                packageLabel(candidate).tag(candidate)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("Take From")
                    } footer: {
                        Text("The package that expires first is suggested, but you can choose any.")
                    }
                }

                Section {
                    HStack {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Amount")
                        Picker("Unit", selection: $unit) {
                            ForEach(package.converter.enterableUnits) { unit in
                                Text(unit.label(for: 2)).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Button("Use All (\(package.remainingText))") {
                        usesEverything = true
                        amountText = NumberInput.text(package.remainingAmount)
                        unit = package.quantityUnit
                    }
                } header: {
                    Text("Amount")
                } footer: {
                    amountFooter
                }

                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(UsageReason.allCases) { reason in
                            Label(reason.displayName, systemImage: reason.systemImage).tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Reason")
                } footer: {
                    Text(reason == .ate ? "Counts toward your food log." : "Doesn't count toward your food log.")
                }

                if reason == .ate {
                    Section("Nutrition") {
                        Text(nutritionText)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    DatePicker("When", selection: $date, in: ...Date.now)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Use Some")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(validMilli == nil)
                }
            }
            // Typing again after "Use all" means the user wants a specific amount.
            .onChange(of: amountText) { _, newValue in
                if usesEverything && newValue != NumberInput.text(package.remainingAmount) {
                    usesEverything = false
                }
            }
            .onChange(of: package) { _, newPackage in
                usesEverything = false
                if !newPackage.converter.enterableUnits.contains(unit) {
                    unit = newPackage.converter.enterableUnits.first ?? newPackage.quantityUnit
                }
            }
        }
    }

    @ViewBuilder
    private var amountFooter: some View {
        switch parsedMilli {
        case .success(let milli):
            Text("Leaves \(package.amountText(milli: package.remainingAmountMilli - milli)).")
        case .failure(let error):
            if amountText.isEmpty {
                Text("\(package.remainingText) left.")
            } else {
                Text(error.localizedDescription).foregroundStyle(.red)
            }
        }
    }

    private var nutritionText: String {
        guard let milli = validMilli else { return "Enter an amount to see nutrition." }
        let facts = package.nutrition(forMilli: milli)
        if let summary = NutritionFormat.summary(facts) {
            return facts.calories == nil ? "\(summary) · calories not entered" : summary
        }
        return "Nutrition not entered for this product."
    }

    private func packageLabel(_ candidate: GroceryItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Bought \(candidate.purchaseDate.formatted(date: .abbreviated, time: .omitted))")
                if candidate == suggestedPackage {
                    Text("Expires first")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Text("\(candidate.remainingText) · \(candidate.freshnessText(now: now))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard let milli = validMilli else { return }
        do {
            try package.use(milli, reason: reason, on: date)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
