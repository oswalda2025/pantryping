//
//  NumberField.swift
//  Pantry Ping
//

import SwiftUI

// Turns what someone typed into a number, accepting both "4.5" and "4,5".
// Empty text means "not entered" (nil), which is different from 0.
enum NumberInput {
    static func double(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: trimmed) {
            return number.doubleValue
        }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    // Money is parsed into Decimal so cents stay exact.
    static func decimal(_ text: String) -> Decimal? {
        let cleaned = text.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned.replacingOccurrences(of: ",", with: "."))
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
