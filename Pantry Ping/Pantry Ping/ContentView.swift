//
//  ContentView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

// The root of the app: five tabs, plus the app-wide "now" clock and reminder scheduling.
// Settings and Saved Products open from the Kitchen tab's "More" menu.
struct ContentView: View {
    // @State lets this view own a value; changing it redraws everything that reads it.
    @State private var now = Date.now

    // @Environment reads values the system provides — here, whether the app is on screen.
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    @AppStorage("remindersEnabled") private var remindersEnabled = true
    // True when the saved database couldn't be opened this launch (see DatabaseLoader).
    @State private var isShowingDatabaseProblem = DatabaseLoader.failedStoreURL != nil
    @State private var isConfirmingFreshStart = false
    @State private var freshStartMessage: String?
    // False until the welcome flow (name + who it's for) has been completed once.
    @AppStorage(ProfileKeys.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    // Active groceries and meals with a date — the only ones reminders care about.
    // Finished or thrown-away items drop out of these queries, which stops their reminders.
    @Query(filter: #Predicate<GroceryItem> { $0.statusRaw == "active" && $0.expirationDate != nil })
    private var datedGroceries: [GroceryItem]
    @Query(filter: #Predicate<PreparedMeal> { $0.statusRaw == "active" && $0.expirationDate != nil })
    private var datedMeals: [PreparedMeal]

    // Plain copies of what reminders need. When any name, date, or date source changes,
    // this array changes, and the `.task(id:)` below reschedules everything.
    private var reminderItems: [ReminderItem] {
        ExpirationReminders.items(from: datedGroceries, meals: datedMeals)
    }

    var body: some View {
        // `Tab` is the iOS 18 way to declare tab bar items.
        TabView {
            Tab("Kitchen", systemImage: "refrigerator") {
                HomeView()
            }
            Tab("Meals", systemImage: "takeoutbag.and.cup.and.straw") {
                MealsView()
            }
            Tab("Log", systemImage: "fork.knife") {
                FoodLogView()
            }
            Tab("Shopping", systemImage: "cart") {
                ShoppingListView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath") {
                HistoryView()
            }
        }
        .environment(\.now, now)
        // A full-screen cover can't be swiped away, so onboarding is finished before use.
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { _ in }
        )) {
            OnboardingView()
        }
        .alert("Saved Data Couldn't Be Opened", isPresented: $isShowingDatabaseProblem) {
            Button("Keep My Data", role: .cancel) {}
            Button("Start Fresh…", role: .destructive) { isConfirmingFreshStart = true }
        } message: {
            Text("Nothing has been deleted. Pantry Ping will try again next time it opens — an app update may fix this. Until then, changes you make won't be saved.")
        }
        .alert("Start Fresh?", isPresented: $isConfirmingFreshStart) {
            Button("Cancel", role: .cancel) {}
            Button("Start Fresh", role: .destructive) {
                let backup = DatabaseLoader.moveAsideForFreshStart()
                freshStartMessage = "Your old data was kept in a backup file (\(backup ?? "unavailable")). Close and reopen Pantry Ping to start with an empty kitchen."
            }
        } message: {
            Text("Your current saved data will be set aside in a backup file, not deleted.")
        }
        .alert("Reopen Pantry Ping", isPresented: Binding(
            get: { freshStartMessage != nil },
            set: { if !$0 { freshStartMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(freshStartMessage ?? "")
        }
        // Refresh "now" whenever the app comes back to the foreground...
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                now = .now
            } else {
                // SwiftData saves automatically, but saving as the app leaves the screen
                // guarantees nothing is lost if iOS closes it in the background.
                try? modelContext.save()
            }
        }
        // ...and at midnight or after a time-zone change while it stays open.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = .now
        }
        // `.task(id:)` runs this async work on appear and again whenever the id changes
        // (groceries edited, reminders toggled, or a new day) — cancelling any older run.
        .task(id: ReminderSchedule(items: reminderItems, enabled: remindersEnabled, now: now,
                                   onboarded: hasCompletedOnboarding)) {
            await updateReminders()
        }
    }

    private func updateReminders() async {
        // Ask for permission the first time there's actually something to remind about,
        // so the system prompt appears in context rather than at first launch.
        // Never while the welcome screens are showing.
        if remindersEnabled && hasCompletedOnboarding && !reminderItems.isEmpty {
            _ = await ExpirationReminders.requestAuthorizationIfNeeded()
        }
        await ExpirationReminders.reschedule(for: reminderItems, enabled: remindersEnabled)
    }
}

// Everything that should trigger a reschedule, bundled so `.task(id:)` can compare it.
// `Equatable` lets SwiftUI tell whether it changed.
private struct ReminderSchedule: Equatable {
    let items: [ReminderItem]
    let enabled: Bool
    let now: Date
    let onboarded: Bool
}

#Preview {
    ContentView()
        .modelContainer(SampleData.previewContainer)
}
