//
//  NumberField.swift
//  Pantry Ping
//

import SwiftUI

// Prices are always in US dollars, whatever region the phone is set to.
// Kept in one place so every screen shows money the same way.
enum Money {
    static let currencyCode = "USD"
    static let symbol = "$"

    // "$4.99"
    static func text(_ amount: Decimal) -> String {
        // US formatting too, so it reads "$4.99" rather than "US$4.99" in other regions.
        amount.formatted(.currency(code: currencyCode).locale(Locale(identifier: "en_US")))
    }
}

// Turns what someone typed into a number. One rule everywhere, whatever the phone's region:
// "4.5" and "4,5" both mean four and a half; "1,000" and "1,299.50" use the comma for thousands.
// Empty text means "not entered" (nil), which is different from 0.
enum NumberInput {
    static func double(_ text: String) -> Double? {
        normalized(text).flatMap(Double.init)
    }

    // Money is parsed into Decimal so cents stay exact.
    static func decimal(_ text: String) -> Decimal? {
        let cleaned = text.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        return normalized(cleaned).flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
    }

    // Rewrites typed text in plain "1234.5" form, or nil if it's empty.
    static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(".") {
            // A dot is the decimal point, so any commas are thousands separators.
            return trimmed.replacingOccurrences(of: ",", with: "")
        }
        let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
        if parts.count == 2, parts[1].count != 3 {
            // One comma not followed by exactly three digits: a decimal comma ("4,5", "0,25").
            return "\(parts[0]).\(parts[1])"
        }
        // "1,000" or "1,000,000": thousands separators.
        return trimmed.replacingOccurrences(of: ",", with: "")
    }

    // The reverse: a number back into editable text ("" for nil).
    static func text(_ value: Double?) -> String {
        value.map { Quantity.number($0, maxFractionDigits: 3) } ?? ""
    }

    static func text(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return "\(value)"
    }
}

// A labeled row with a number field on the right, e.g. "Calories  [260] kcal".
// It edits text (not a number directly) so half-typed values like "4." aren't lost.
struct NumberField: View {
    let title: String
    @Binding var text: String
    var placeholder = "Optional"
    var suffix: String?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                .accessibilityLabel(title)
            if let suffix {
                Text(suffix)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// Small colored text used to label suggested dates so they never look like entered ones.
struct SuggestedTag: View {
    var body: some View {
        Text("Suggested")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.purple.opacity(0.15), in: Capsule())
            .foregroundStyle(.purple)
            .accessibilityLabel("Suggested date")
    }
}

// Number keypads have no return key, so forms with number fields get a "Done" button
// above the keyboard, and dragging the form also dismisses the keyboard.
struct KeyboardDoneButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        // Asks whichever field has the keyboard to give it up.
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                    }
                }
            }
    }
}

extension View {
    func keyboardDoneButton() -> some View {
        modifier(KeyboardDoneButton())
    }
}
