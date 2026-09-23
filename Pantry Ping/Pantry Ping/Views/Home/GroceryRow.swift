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
            // The product photo when there is one; otherwise the urgency icon.
            // Either way the urgency text on the right says it in words.
            if let photo = item.product?.photoData {
                ProductThumbnail(data: photo, size: 36)
            } else {
                Image(systemName: status.systemImage)
                    .font(.title3)
                    .foregroundStyle(status.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body.weight(.medium))
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

    // "Pantry · 279 g · 4.5 servings", or "Freezer · Frozen" once the food state has changed.
    private var locationLine: String {
        var parts = [item.storageLocation.displayName]
        if item.foodState != .fresh {
            parts.append(item.foodState.displayName)
        }
        if item.hasMeaningfulAmount {
            parts.append(item.remainingText)
        }
        // With several open packages of the same product, the purchase date tells them apart.
        if (item.product?.activePackages.count ?? 0) > 1 {
            parts.append("Bought \(item.purchaseDate.formatted(.dateTime.day().month(.abbreviated)))")
        }
        return parts.joined(separator: " · ")
    }

    private func freshnessColor(for status: ExpirationStatus) -> Color {
        switch status {
        case .expired: .red
        case .urgent: .orange
        default: .secondary
        }
    }
}
