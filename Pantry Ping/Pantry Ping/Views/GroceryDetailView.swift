//
//  GroceryDetailView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

// Everything about one grocery, plus the actions that change it:
// Used / Thrown Away, food-state changes, edit, and delete.
struct GroceryDetailView: View {
    // SwiftData models are observable: when a property of `item` changes,
    // this view redraws automatically — no @State needed.
    let item: GroceryItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.now) private var now

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    // Deleting waits until this screen has closed, so it never shows a deleted item.
    @State private var deleteWhenClosed = false
    // Which date sheet is showing. An enum keeps the two kinds from overlapping.
    @State private var dateSheet: DateSheet?

    private enum DateSheet: Identifiable {
        case stateChange(FoodState)
        case updateDate

        var id: String {
            switch self {
            case .stateChange(let state): state.rawValue
            case .updateDate: "updateDate"
            }
        }
    }

    var body: some View {
        // The item may have been deleted elsewhere (e.g. from another tab) while this
        // screen was still open. Reading a deleted SwiftData model can crash, so check first.
        if item.isDeleted || item.modelContext == nil {
            ContentUnavailableView("Grocery deleted", systemImage: "trash")
        } else {
            details
        }
    }

    @ViewBuilder
    private var details: some View {
        let status = item.expirationStatus(now: now)

        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(item.freshnessText(now: now), systemImage: status.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(status == .noDate ? Color.primary : status.tint)
                    Text(summaryLine)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if item.status == .active && (status == .expired || item.shouldSuggestUseByDate) {
                    VStack(alignment: .leading, spacing: 8) {
                        if status == .expired {
                            Text(FoodState.expiredGuidance)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Button(status == .expired ? "Still Have It — Update Date" : "Add a Use-By Date") {
                            dateSheet = .updateDate
                        }
                    }
                }
            }

            if item.status == .active {
                activeActions
            } else {
                resolvedSection
            }

            detailsSection

            Section {
                Button("Delete Grocery", role: .destructive) {
                    isConfirmingDelete = true
                }
            } footer: {
                Text("Deleting removes it completely. To keep your history, mark it Used or Thrown Away instead.")
            }
        }
        .navigationTitle(item.name)
        .toolbar {
            Button("Edit") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            GroceryFormView(item: item)
        }
        .sheet(item: $dateSheet) { sheet in
            switch sheet {
            case .stateChange(let state):
                UseByDateSheet(item: item, newState: state)
            case .updateDate:
                UseByDateSheet(item: item, newState: nil)
            }
        }
        .confirmationDialog("Delete \(item.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteWhenClosed = true
                dismiss()
            }
        }
        .onDisappear {
            if deleteWhenClosed {
                modelContext.delete(item)
            }
        }
    }

    // "Fridge · Dairy & Eggs · ×2"
    private var summaryLine: String {
        var parts = [item.storageLocation.displayName, item.category.displayName]
        if item.quantity != 1 {
            parts.append("×\(item.quantity.formatted())")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Sections

    private var activeActions: some View {
        Group {
            Section {
                Button("Mark as Used", systemImage: "checkmark.circle") {
                    item.status = .used
                    dismiss()
                }
                .tint(.green)
                Button("Thrown Away", systemImage: "trash") {
                    item.status = .discarded
                    dismiss()
                }
                .tint(.red)
            }

            Section {
                // One button per state this food can move to next, e.g. Freeze or Thaw.
                ForEach(item.foodState.nextStates) { state in
                    Button(state.actionName, systemImage: state.systemImage) {
                        dateSheet = .stateChange(state)
                    }
                }
            } header: {
                Text("Food State: \(item.foodState.displayName)")
            }
        }
    }

    private var resolvedSection: some View {
        Section {
            if let resolved = item.dateResolved {
                LabeledContent(item.status.displayName, value: resolved.formatted(date: .abbreviated, time: .omitted))
            }
            Button("Move Back to Kitchen", systemImage: "arrow.uturn.backward") {
                item.status = .active
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            dateRow("Use by", item.expirationDate, fallback: "No date")
            if item.originalExpirationDate != item.expirationDate {
                dateRow("Original date", item.originalExpirationDate, fallback: "None")
            }
            dateRow("Purchased", item.purchaseDate)
            dateRow("Opened", item.dateOpened)
            dateRow("Cooked", item.dateCooked)
            dateRow("Frozen", item.dateFrozen)
            dateRow("Thawed", item.dateThawed)
            dateRow("Added", item.dateAdded)
            if !item.notes.isEmpty {
                LabeledContent("Notes", value: item.notes)
            }
        }
    }

    // Shows a labeled date, hiding the row entirely when there's no date and no fallback.
    @ViewBuilder
    private func dateRow(_ title: String, _ date: Date?, fallback: String? = nil) -> some View {
        if let date {
            LabeledContent(title, value: date.formatted(date: .abbreviated, time: .omitted))
        } else if let fallback {
            LabeledContent(title, value: fallback)
        }
    }
}

#Preview {
    NavigationStack {
        GroceryDetailView(item: SampleData.previewSampleItem)
    }
    .modelContainer(SampleData.previewContainer)
}
