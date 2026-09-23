//
//  EatPortionSheet.swift
//  Pantry Ping
//

import SwiftUI

// Logs eating some of a prepared meal, by portion or by weight, and reduces what's left.
struct EatPortionSheet: View {
    let meal: PreparedMeal

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var unit: MeasureUnit
    @State private var date = Date.now
    @State private var errorMessage: String?

    init(meal: PreparedMeal) {
        self.meal = meal
        let firstUnit = meal.enterableUnits.first ?? meal.quantityUnit
        _unit = State(initialValue: firstUnit)
        // One portion is the common case; weights start empty.
        _amountText = State(initialValue: firstUnit == .portion ? "1" : "")
    }

    private var parsedMilli: Result<Int, InventoryError> {
        guard let value = NumberInput.double(amountText) else { return .failure(.invalidAmount) }
        do {
            let milli = try meal.milli(for: value, unit: unit)
            guard milli <= meal.remainingAmountMilli else {
                return .failure(.notEnoughLeft(available: meal.remainingText))
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
                Section {
                    HStack {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Amount")
                        Picker("Unit", selection: $unit) {
                            ForEach(meal.enterableUnits) { unit in
                                Text(unit.label(for: 2)).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                } header: {
                    Text("How Much")
                } footer: {
                    switch parsedMilli {
                    case .success(let milli):
                        Text("Leaves \(meal.amountText(milli: meal.remainingAmountMilli - milli)).")
                    case .failure(let error):
                        Text(amountText.isEmpty ? "\(meal.remainingText) left." : error.localizedDescription)
                            .foregroundStyle(amountText.isEmpty ? Color.secondary : Color.red)
                    }
                }

                Section("Nutrition") {
                    if let milli = validMilli, let summary = NutritionFormat.summary(meal.nutrition(forMilli: milli)) {
                        Text(summary).foregroundStyle(.secondary)
                    } else {
                        Text(meal.batchNutrition.isEmpty ? "Nutrition not entered for this meal." : "Enter an amount to see nutrition.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    DatePicker("When", selection: $date, in: ...Date.now)
                } footer: {
                    Text("Counts toward your food log.")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Eat \(meal.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let milli = validMilli else { return }
                        do {
                            try meal.eat(milli, on: date)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(validMilli == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
