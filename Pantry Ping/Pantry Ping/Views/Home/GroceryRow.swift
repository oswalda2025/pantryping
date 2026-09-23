//
//  GroceryRow.swift
//  Pantry Ping
//

import SwiftUI

// One grocery in a list: name, where it is, and how urgent it is.
struct GroceryRow: View {
    let item: GroceryItem
    @Environment(\.now) private var now

    var body: some View {
        let status = item.expirationStatus(now: now)

        HStack(spacing: 12) {
            // Icon + text together, so urgency never depends on color alone.
            Image(systemName: status.systemImage)
                .font(.title3)
                .foregroundStyle(status.tint)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.body.weight(.medium))
                    if item.quantity != 1 {
                        Text("×\(item.quantity.formatted())")
                            .foregroundStyle(.secondary)
                    }
                }
                Text(locationLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if item.shouldSuggestUseByDate {
                    Text("Add a use-by date?")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }

            Spacer(minLength: 8)

            Text(item.freshnessText(now: now))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(freshnessColor(for: status))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
        // Reads the whole row as one sentence in VoiceOver.
        .accessibilityElement(children: .combine)
    }

    // "Fridge", or "Freezer · Frozen" once the food state has changed.
    private var locationLine: String {
        let location = item.storageLocation.displayName
        return item.foodState == .fresh ? location : "\(location) · \(item.foodState.displayName)"
    }

    private func freshnessColor(for status: ExpirationStatus) -> Color {
        switch status {
        case .expired: .red
        case .urgent: .orange
        default: .secondary
        }
    }
}
