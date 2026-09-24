//
//  SettingsView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @AppStorage("remindersEnabled") private var remindersEnabled = true
    @AppStorage(ProfileKeys.name) private var name = ""
    @AppStorage(ProfileKeys.householdType) private var householdRaw = HouseholdType.solo.rawValue
    @AppStorage(FoodLookup.usdaKeyStorageKey) private var usdaKey = ""

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    // True when the user has turned notifications off for Pantry Ping in iOS Settings.
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Set up for", selection: $householdRaw) {
                        ForEach(HouseholdType.allCases) { type in
                            Label(type.title, systemImage: type.systemImage).tag(type.rawValue)
                        }
                    }
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Your profile and groceries are stored only on this iPhone. Signing in with Apple and iCloud backup are planned for a later version.")
                }

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
                    TextField("USDA API key (optional)", text: $usdaKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                    if let signUp = URL(string: "https://fdc.nal.usda.gov/api-key-signup") {
                        Link("Get a Free USDA Key", destination: signUp)
                    }
                } header: {
                    Text("Barcode Lookup")
                } footer: {
                    Text(usdaKey.isEmpty
                         ? "Scanning checks USDA FoodData Central, then Open Food Facts. Without your own free key, USDA allows only a few lookups per hour, so most scans will use Open Food Facts. Only the barcode number is sent."
                         : "Scanning checks USDA FoodData Central with your key, then Open Food Facts. Only the barcode number is sent.")
                }

                // Developer-only: in the real app this would mix fake groceries (and Food Log
                // entries) into real data with no easy way to remove them. New users still get
                // "Try Sample Groceries" on the empty Kitchen screen.
                #if DEBUG
                Section {
                    Button("Add Sample Groceries") {
                        SampleData.insertSampleGroceries(into: modelContext)
                    }
                } footer: {
                    Text("Developer builds only. Adds demo groceries to your real data.")
                }
                #endif

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
