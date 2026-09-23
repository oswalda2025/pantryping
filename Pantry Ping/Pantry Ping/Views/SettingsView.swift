//
//  SettingsView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("remindersEnabled") private var remindersEnabled = true

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Expiration Reminders", isOn: $remindersEnabled)
                } footer: {
                    Text("A daily reminder at 9 AM when groceries have 3, 2, 1, or 0 days left.")
                }

                Section {
                    Button("Add Sample Groceries") {
                        SampleData.insertSampleGroceries(into: modelContext)
                    }
                } footer: {
                    Text("Adds a set of demo groceries so you can explore the app.")
                }

                Section("About") {
                    Text(FoodState.disclaimer)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    LabeledContent("Data", value: "Stored only on this device")
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

#Preview {
    SettingsView()
        .modelContainer(SampleData.previewContainer)
}
