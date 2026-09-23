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

    @AppStorage("remindersEnabled") private var remindersEnabled = true

    // Active groceries and meals with a date — the only ones reminders care about.
    // Finished or thrown-away items drop out of these queries, which stops their reminders.
    @Query(filter: #Predicate<GroceryItem> { $0.statusRaw == "active" && $0.expirationDate != nil })
    private var datedGroceries: [GroceryItem]
    @Query(filter: #Predicate<PreparedMeal> { $0.statusRaw == "active" && $0.expirationDate != nil })
    private var datedMeals: [PreparedMeal]

    // Plain copies of what reminders need. When any name, date, or date source changes,
    // this array changes, and the `.task(id:)` below reschedules everything.
    private var reminderItems: [ReminderItem] {
        let groceries = datedGroceries.compactMap { item in
            item.expirationDate.map {
                ReminderItem(name: item.displayName, expirationDate: $0, isSuggested: item.expirationSource == .suggested)
            }
        }
        let meals = datedMeals.compactMap { meal in
            meal.expirationDate.map {
                ReminderItem(name: meal.name, expirationDate: $0, isSuggested: meal.expirationSource == .suggested)
            }
        }
        return groceries + meals
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
        // Refresh "now" whenever the app comes back to the foreground...
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                now = .now
            }
        }
        // ...and at midnight or after a time-zone change while it stays open.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = .now
        }
        // `.task(id:)` runs this async work on appear and again whenever the id changes
        // (groceries edited, reminders toggled, or a new day) — cancelling any older run.
        .task(id: ReminderSchedule(items: reminderItems, enabled: remindersEnabled, now: now)) {
            await updateReminders()
        }
    }

    private func updateReminders() async {
        // Ask for permission the first time there's actually something to remind about,
        // so the system prompt appears in context rather than at first launch.
        if remindersEnabled && !reminderItems.isEmpty {
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
}

#Preview {
    ContentView()
        .modelContainer(SampleData.previewContainer)
}
