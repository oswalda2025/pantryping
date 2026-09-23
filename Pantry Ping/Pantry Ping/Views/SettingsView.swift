//
//  SettingsView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @AppStorage("remindersEnabled") private var remindersEnabled = true

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    // True when the user has turned notifications off for Pantry Ping in iOS Settings.
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Expiration Reminders", isOn: $remindersEnabled)
                    if remindersEnabled && notificationsDenied,
                       let settingsURL = URL(string: UIApplication.openNotificationSettingsURLString) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Notifications are off for Pantry Ping in iOS Settings.", systemImage: "bell.slash")
                                .foregroundStyle(.orange)
                            Link("Open Settings", destination: settingsURL)
                        }
                        .font(.callout)
                    }
                } footer: {
                    Text("A daily reminder at 9 AM when groceries or prepared meals have 3, 2, 1, or 0 days left. Finished and thrown-away items never get reminders.")
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Re-check whenever the user returns, e.g. after changing it in iOS Settings.
            .task(id: scenePhase) {
                let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                notificationsDenied = status == .denied
            }
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
