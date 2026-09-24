//
//  EditForms.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

// Edits one package: where it's stored, its price, dates, and notes.
// The product's own details (name, nutrition, photo) are edited in EditProductView.
struct EditPackageView: View {
    let item: GroceryItem

    @Environment(\.dismiss) private var dismiss

    @State private var location: StorageLocation
    @State private var priceText: String
    @State private var purchaseDate: Date
    @State private var hasUseByDate: Bool
    @State private var useByDate: Date
    @State private var notes: String
    @State private var errorMessage: String?

    // `_name = State(initialValue:)` sets a @State property's starting value from the item.
    init(item: GroceryItem) {
        self.item = item
        _location = State(initialValue: item.storageLocation)
        _priceText = State(initialValue: NumberInput.text(item.price))
        _purchaseDate = State(initialValue: item.purchaseDate)
        _hasUseByDate = State(initialValue: item.expirationDate != nil)
        _useByDate = State(initialValue: item.expirationDate ?? .now)
        _notes = State(initialValue: item.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Stored In") {
                    Picker("Stored In", selection: $location) {
                        ForEach(StorageLocation.allCases) { location in
                            Text(location.displayName).tag(location)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    Toggle("Use-by date", isOn: $hasUseByDate.animation())
                    if hasUseByDate {
                        DatePicker("Date", selection: $useByDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Use By")
                } footer: {
                    if hasUseByDate && Calendar.current.startOfDay(for: useByDate) < Calendar.current.startOfDay(for: purchaseDate) {
                        Text("The use-by date is before the purchase date — double-check it.")
                            .foregroundStyle(.orange)
                    } else if item.expirationSource == .suggested {
                        Text("The current date is a suggestion from general guidance. Changing it makes it your own date.")
                    }
                }

                Section {
                    HStack {
                        Text("Price")
                        Spacer()
                        Text(Money.symbol).foregroundStyle(.secondary)
                        TextField("Optional", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                            .accessibilityLabel("Price")
                    }
                    DatePicker("Purchased", selection: $purchaseDate, in: ...Date.now, displayedComponents: .date)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit \(item.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
    }

    private func save() {
        if !priceText.isEmpty && NumberInput.decimal(priceText) == nil {
            errorMessage = "Enter the price as a number."
            return
        }
        item.move(to: location)
        item.price = NumberInput.decimal(priceText)
        item.purchaseDate = CalendarDay.noon(purchaseDate)
        item.notes = notes
        // Only touch the date when it actually changed, so an unchanged date keeps its
        // source (e.g. "suggested") and the original package date isn't overwritten.
        let newDate = hasUseByDate ? useByDate : nil
        if dateChanged(from: item.expirationDate, to: newDate) {
            item.setUseByDate(newDate, isCorrection: true)
        }
        dismiss()
    }

    private func dateChanged(from old: Date?, to new: Date?) -> Bool {
        switch (old, new) {
        case (nil, nil): false
        case let (old?, new?): !Calendar.current.isDate(old, inSameDayAs: new)
        default: true
        }
    }
}

// Edits a saved product's reusable details. Changes apply to every package of it.
struct EditProductView: View {
    let product: Product

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProductDraft
    @State private var errorMessage: String?

    init(product: Product) {
        self.product = product
        _draft = State(initialValue: ProductDraft(product: product))
    }

    var body: some View {
        NavigationStack {
            Form {
                ProductFields(draft: $draft)
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit Product")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let problem = draft.problem {
                            errorMessage = problem
                        } else {
                            draft.apply(to: product)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
