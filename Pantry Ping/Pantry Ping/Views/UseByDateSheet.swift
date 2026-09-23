//
//  UseByDateSheet.swift
//  Pantry Ping
//

import SwiftUI

// A small sheet for changing an item's use-by date — either as part of a food-state
// change (Open, Cook, Freeze, Thaw) or on its own ("Still have it?", "Add a use-by date?").
// It shows general guidance but never fills in a duration for the user.
struct UseByDateSheet: View {
    let item: GroceryItem
    // nil = only updating the date, without changing the food state.
    let newState: FoodState?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.now) private var now

    @State private var hasDate: Bool
    @State private var date: Date

    init(item: GroceryItem, newState: FoodState?) {
        self.item = item
        self.newState = newState
        if let newState {
            // Opening keeps the package date; other changes start with no date.
            _hasDate = State(initialValue: newState.keepsExistingDateByDefault && item.expirationDate != nil)
        } else {
            _hasDate = State(initialValue: true)
        }
        if let newState, newState.keepsExistingDateByDefault, let existing = item.expirationDate {
            // Keeping the package date means keeping it exactly — even if it has passed.
            _date = State(initialValue: existing)
        } else {
            // A new date starts on the current one if it's still ahead, otherwise today.
            _date = State(initialValue: max(item.expirationDate ?? .now, .now))
        }
    }

    private var title: String {
        if let newState {
            return "\(newState.actionName) \(item.name)"
        }
        return "Update Use-By Date"
    }

    private var guidance: String {
        if let newState {
            return newState.guidance(from: item.foodState)
        }
        if item.expirationStatus(now: now) == .expired {
            return FoodState.expiredGuidance
        }
        return "Set the date you plan to use this by. Check the label if you're not sure."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(guidance, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Set a use-by date", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("Use by", selection: $date, displayedComponents: .date)
                    }
                } footer: {
                    if let newState, newState != .opened, !hasDate {
                        Text("Without a date, Pantry Ping will show how long ago it was \(newState.displayName.lowercased()).")
                    }
                }

                if let location = newState?.impliedLocation, location != item.storageLocation {
                    Section {
                        Label("Moves to \(location.displayName)", systemImage: "arrow.right.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(newState?.actionName ?? "Save", action: confirm)
                }
            }
        }
        // Detents let the sheet stop at half height.
        .presentationDetents([.medium, .large])
    }

    private func confirm() {
        let chosenDate = hasDate ? date : nil
        withAnimation {
            if let newState {
                item.changeFoodState(to: newState, newExpirationDate: chosenDate, on: now)
            } else {
                item.setUseByDate(chosenDate, isCorrection: false)
            }
        }
        dismiss()
    }
}
