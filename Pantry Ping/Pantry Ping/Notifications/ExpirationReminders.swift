//
//  ExpirationReminders.swift
//  Pantry Ping
//
//  Plans and schedules local "use it soon" reminders.
//  Deliberately knows nothing about SwiftData or GroceryItem: callers hand in
//  plain values, which keeps the planning logic pure and easy to unit test.
//

import Foundation
import UserNotifications

/// The minimum an item needs to contribute to a reminder.
/// `nonisolated` opts these plain value types out of the app target's default
/// MainActor isolation, so they can be created and compared from any context.
nonisolated struct ReminderItem: Equatable, Sendable {
    let name: String
    /// The item's current use-by day (stored at 12:00 local time).
    let expirationDate: Date
}

/// One notification we intend to schedule.
nonisolated struct PlannedReminder: Equatable, Sendable {
    let identifier: String
    /// Floating local wall-clock time (no time zone), for a `UNCalendarNotificationTrigger`.
    let fireDate: DateComponents
    let title: String
    let body: String
}

/// A caseless enum used as a namespace: it can't be instantiated, and its
/// static functions hold no state, so there is no "manager" object to keep alive.
enum ExpirationReminders {
    nonisolated static let identifierPrefix = "pantryping.reminder."
    nonisolated static let reminderHour = 9

    /// An item is mentioned on each of these days before (and on) its expiration day.
    private nonisolated static let leadDays = 0...3
    /// How far ahead we plan, in days after today.
    private nonisolated static let horizonDays = 60
    private nonisolated static let maxNamesInBody = 3

    // MARK: - Planning (pure)

    /// Builds one digest reminder per calendar day on which at least one item
    /// has 3, 2, 1 or 0 days left. Pure: same input, same output, no side effects.
    nonisolated static func plan(
        for items: [ReminderItem],
        now: Date,
        calendar: Calendar,
        hour: Int = reminderHour,
        maxCount: Int = 60
    ) -> [PlannedReminder] {
        guard maxCount > 0 else { return [] }
        let today = calendar.startOfDay(for: now)

        // Group items by the day (as an offset from today) on which they should be
        // mentioned. Working backwards from each expiration day means we only touch
        // the four relevant days per item instead of scanning the whole 60-day window.
        var itemsByDayOffset: [Int: [(item: ReminderItem, daysLeft: Int)]] = [:]
        for item in items {
            let expirationDay = calendar.startOfDay(for: item.expirationDate)
            // Count calendar days, not seconds / 86400: a DST change makes some days
            // 23 or 25 hours long, which would break the division.
            guard let expiryOffset = calendar.dateComponents([.day], from: today, to: expirationDay).day else {
                continue
            }
            for daysLeft in leadDays {
                let offset = expiryOffset - daysLeft
                // Negative offsets are days already gone; this also drops expired items.
                guard (0...horizonDays).contains(offset) else { continue }
                itemsByDayOffset[offset, default: []].append((item, daysLeft))
            }
        }

        var reminders: [PlannedReminder] = []
        for offset in itemsByDayOffset.keys.sorted() {
            guard reminders.count < maxCount else { break }
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: today),
                let fireDate = fireComponents(for: day, hour: hour, calendar: calendar),
                let fireInstant = calendar.date(from: fireDate),
                fireInstant > now // e.g. it's already past 9:00 today
            else { continue }

            let entries = itemsByDayOffset[offset, default: []].sorted { lhs, rhs in
                if lhs.daysLeft != rhs.daysLeft { return lhs.daysLeft < rhs.daysLeft }
                return lhs.item.name < rhs.item.name
            }
            let (title, body) = message(for: entries)
            reminders.append(PlannedReminder(
                identifier: identifier(for: fireDate),
                fireDate: fireDate,
                title: title,
                body: body
            ))
        }
        return reminders
    }

    // MARK: - Scheduling (system)

    /// Asks for permission only if the user hasn't decided yet; returns whether alerts are allowed.
    /// `async` lets the caller `await` the system prompt without blocking the main thread.
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// Replaces all of our pending reminders with a fresh plan.
    /// Always removes first, so turning reminders off (or losing permission) clears them.
    static func reschedule(for items: [ReminderItem], enabled: Bool) async {
        let center = UNUserNotificationCenter.current()

        let ours = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard enabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        for reminder in plan(for: items, now: Date(), calendar: .current) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default

            // A DateComponents trigger with no time zone fires at that wall-clock time
            // wherever the user is, and stays at 9:00 across DST changes.
            let trigger = UNCalendarNotificationTrigger(dateMatching: reminder.fireDate, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
            // One failed add (rare) shouldn't stop the rest from being scheduled.
            try? await center.add(request)
        }
    }

    // MARK: - Helpers

    private nonisolated static func fireComponents(for day: Date, hour: Int, calendar: Calendar) -> DateComponents? {
        let ymd = calendar.dateComponents([.year, .month, .day], from: day)
        guard let year = ymd.year, let month = ymd.month, let dayOfMonth = ymd.day else { return nil }
        return DateComponents(year: year, month: month, day: dayOfMonth, hour: hour, minute: 0)
    }

    /// "pantryping.reminder.yyyy-MM-dd", built from numbers so it never depends on
    /// the user's locale or calendar settings (unlike a DateFormatter).
    private nonisolated static func identifier(for components: DateComponents) -> String {
        let year = components.year ?? 0, month = components.month ?? 0, day = components.day ?? 0
        return identifierPrefix + String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Wording talks about the date only; we never claim food is unsafe or spoiled.
    private nonisolated static func message(for entries: [(item: ReminderItem, daysLeft: Int)]) -> (title: String, body: String) {
        if entries.count == 1, let only = entries.first {
            let name = only.item.name
            let title: String
            switch only.daysLeft {
            case 0: title = "\(name) expires today"
            case 1: title = "\(name) expires tomorrow"
            default: title = "\(name): \(only.daysLeft) days left"
            }
            return (title, "Open Pantry Ping to use it, freeze it, or mark it used.")
        }

        var parts = entries.prefix(maxNamesInBody).map { entry -> String in
            switch entry.daysLeft {
            case 0: return "\(entry.item.name) expires today"
            case 1: return "\(entry.item.name) expires tomorrow"
            default: return "\(entry.item.name) in \(entry.daysLeft) days"
            }
        }
        let remaining = entries.count - maxNamesInBody
        if remaining > 0 {
            parts.append("and \(remaining) more")
        }
        return ("\(entries.count) items need attention", parts.joined(separator: " · "))
    }
}
