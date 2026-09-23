//
//  PackageFields.swift
//  Pantry Ping
//

import SwiftUI

// The details of ONE purchased package: its size, price, dates, and where it's stored.
struct PackageDraft {
    var amountText = "1"
    var unit = MeasureUnit.piece
    var priceText = ""
    var purchaseDate = Date.now
    var hasUseByDate = false
    var useByDate = Date.now
    var storageLocation: StorageLocation
    var notes = ""

    // Starts from the product's usual package size, when it's known.
    init(product: Product?) {
        let lastLocation = UserDefaults.standard.string(forKey: "lastStorageLocation")
        storageLocation = lastLocation.flatMap(StorageLocation.init(rawValue:)) ?? .fridge
        if let servings = product?.servingsPerPackage {
            amountText = NumberInput.text(servings)
            unit = .serving
        } else if let servingUnit = product?.servingUnit, product?.servingSize != nil {
            // Default to the serving's own kind of unit (e.g. grams) so the size can be typed directly.
            unit = servingUnit.baseUnit
            amountText = ""
        }
    }

    var amount: Double? { NumberInput.double(amountText) }
    var price: Decimal? { NumberInput.decimal(priceText) }
    var expirationDate: Date? { hasUseByDate ? useByDate : nil }

    var problem: String? {
        guard let amount, amount > 0 else { return "Enter the package size." }
        if !priceText.isEmpty && price == nil { return "Enter the price as a number." }
        return nil
    }

    static func rememberLocation(_ location: StorageLocation) {
        UserDefaults.standard.set(location.rawValue, forKey: "lastStorageLocation")
    }
}

// Form sections for a package. `units` are the units its size can be entered in.
struct PackageFields: View {
    @Binding var draft: PackageDraft
    let units: [MeasureUnit]
    @Environment(\.now) private var now

    var body: some View {
        Section {
            HStack {
                Text("Package size")
                Spacer()
                TextField("Amount", text: $draft.amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                    .accessibilityLabel("Package size")
                Picker("Package unit", selection: $draft.unit) {
                    ForEach(units) { unit in
                        Text(unit.label(for: 2)).tag(unit)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            HStack {
                Text("Price")
                Spacer()
                Text(Money.symbol)
                    .foregroundStyle(.secondary)
                TextField("Optional", text: $draft.priceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    .accessibilityLabel("Price")
            }
            DatePicker("Purchased", selection: $draft.purchaseDate, in: ...Date.now, displayedComponents: .date)
        } header: {
            Text("This Package")
        }

        Section {
            Toggle("Use-by date", isOn: $draft.hasUseByDate.animation())
            if draft.hasUseByDate {
                DatePicker("Date", selection: $draft.useByDate, displayedComponents: .date)
            }
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
            Text("Use the date on the package. Leave it off for things like rice or canned goods.")
        }

        Section("Stored In") {
            Picker("Stored In", selection: $draft.storageLocation) {
                ForEach(StorageLocation.allCases) { location in
                    Text(location.displayName).tag(location)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(1...4)
        }
    }

    private func quickPick(_ title: String, days: Int) -> some View {
        Button(title) {
            withAnimation {
                draft.useByDate = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
                draft.hasUseByDate = true
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
