//
//  GroceryFormView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

// Add a new grocery, or edit an existing one. Only the name is required, so adding
// an item takes seconds; everything else has a sensible default.
struct GroceryFormView: View {
    // nil when adding; the item being edited otherwise.
    let item: GroceryItem?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.now) private var now

    // @AppStorage keeps a small value in UserDefaults: here, the last location picked,
    // since people often add several items to the same place in a row.
    @AppStorage("lastStorageLocation") private var lastLocationRaw = StorageLocation.fridge.rawValue

    @State private var name: String
    @State private var quantity: Double
    @State private var location: StorageLocation
    @State private var category: GroceryCategory
    @State private var hasUseByDate: Bool
    @State private var useByDate: Date
    @State private var purchaseDate: Date
    @State private var notes: String

    // @FocusState tracks which text field has the keyboard.
    @FocusState private var isNameFocused: Bool

    // A custom init fills the form from the item being edited. `_name = State(...)`
    // sets a @State property's starting value.
    init(item: GroceryItem? = nil) {
        self.item = item
        let lastLocation = StorageLocation(
            rawValue: UserDefaults.standard.string(forKey: "lastStorageLocation") ?? ""
        ) ?? .fridge

        _name = State(initialValue: item?.name ?? "")
        _quantity = State(initialValue: item?.quantity ?? 1)
        _location = State(initialValue: item?.storageLocation ?? lastLocation)
        _category = State(initialValue: item?.category ?? .other)
        _hasUseByDate = State(initialValue: item?.expirationDate != nil)
        _useByDate = State(initialValue: item?.expirationDate ?? .now)
        _purchaseDate = State(initialValue: item?.purchaseDate ?? .now)
        _notes = State(initialValue: item?.notes ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Milk", text: $name)
                        .focused($isNameFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                    // Integer-only for now; fractional amounts arrive with units.
                    Stepper(value: $quantity, in: 1...99, step: 1) {
                        Text("Quantity: \(quantity.formatted())")
                    }
                }

                useBySection

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
                    Picker("Category", selection: $category) {
                        ForEach(GroceryCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    DatePicker("Purchased", selection: $purchaseDate, displayedComponents: .date)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("More Details")
                }
            }
            .navigationTitle(item == nil ? "Add Grocery" : "Edit Grocery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                if item == nil {
                    isNameFocused = true
                }
            }
        }
    }

    private var useBySection: some View {
        Section {
            Toggle("Use-by date", isOn: $hasUseByDate.animation())
            if hasUseByDate {
                DatePicker("Date", selection: $useByDate, displayedComponents: .date)
            }
            // Quick picks for the common cases, so most people never open the calendar.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    quickPick("Today", days: 0)
                    quickPick("+3 days", days: 3)
                    quickPick("+1 week", days: 7)
                    quickPick("+2 weeks", days: 14)
                }
            }
        } header: {
            Text("Use By")
        } footer: {
            if hasUseByDate && Calendar.current.startOfDay(for: useByDate) < Calendar.current.startOfDay(for: purchaseDate) {
                Text("The use-by date is before the purchase date — double-check it.")
                    .foregroundStyle(.orange)
            } else {
                Text("Use the date on the package. Leave it off for things like rice or canned goods.")
            }
        }
    }

    private func quickPick(_ title: String, days: Int) -> some View {
        Button(title) {
            withAnimation {
                useByDate = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
                hasUseByDate = true
            }
        }
        // A bordered style keeps each button tappable on its own inside a Form row.
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func save() {
        let date = hasUseByDate ? useByDate : nil
        if let item {
            item.name = trimmedName
            item.quantity = quantity
            item.storageLocation = location
            item.category = category
            item.purchaseDate = GroceryItem.calendarDay(purchaseDate)
            item.notes = notes
            // Only touch dates the user actually changed; re-saving an unchanged date
            // would overwrite the original package date for fresh items.
            if useByDateChanged(from: item.expirationDate, to: date) {
                item.setUseByDate(date, isCorrection: true)
            }
        } else {
            let newItem = GroceryItem(
                name: trimmedName,
                category: category,
                storageLocation: location,
                quantity: quantity,
                purchaseDate: purchaseDate,
                expirationDate: date,
                notes: notes
            )
            // insert() adds the new item to the database; SwiftData saves it automatically.
            modelContext.insert(newItem)
            lastLocationRaw = location.rawValue
        }
        dismiss()
    }

    private func useByDateChanged(from old: Date?, to new: Date?) -> Bool {
        switch (old, new) {
        case (nil, nil): false
        case let (old?, new?): !Calendar.current.isDate(old, inSameDayAs: new)
        default: true
        }
    }
}

#Preview("Add") {
    GroceryFormView()
        .modelContainer(SampleData.previewContainer)
}
