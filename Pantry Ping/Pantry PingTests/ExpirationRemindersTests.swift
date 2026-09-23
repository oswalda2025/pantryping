//
//  ExpirationRemindersTests.swift
//  Pantry PingTests
//
//  Exercises the pure `ExpirationReminders.plan` function with a fixed
//  calendar, time zone and "now", so results never depend on the machine running them.
//

import Foundation
import Testing
@testable import Pantry_Ping

@MainActor
struct ExpirationRemindersTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    /// A wall-clock moment in the test calendar's time zone.
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Items store their use-by day at 12:00 local, like the app does.
    private func item(_ name: String, expires year: Int, _ month: Int, _ day: Int) -> ReminderItem {
        ReminderItem(name: name, expirationDate: date(year, month, day))
    }

    private func ymd(_ reminder: PlannedReminder) -> [Int?] {
        [reminder.fireDate.year, reminder.fireDate.month, reminder.fireDate.day]
    }

    private let singleBody = "Open Pantry Ping to use it, freeze it, or mark it used."

    @Test func singleItemGetsFourRemindersCountingDown() {
        let now = date(2026, 9, 22, 8, 0)
        let plan = ExpirationReminders.plan(for: [item("Milk", expires: 2026, 9, 25)], now: now, calendar: calendar)

        #expect(plan.count == 4)
        #expect(plan.map(ymd) == [[2026, 9, 22], [2026, 9, 23], [2026, 9, 24], [2026, 9, 25]])
        #expect(plan.map(\.title) == [
            "Milk: 3 days left",
            "Milk: 2 days left",
            "Milk expires tomorrow",
            "Milk expires today",
        ])
        #expect(plan.allSatisfy { $0.body == singleBody })
        #expect(plan.allSatisfy { $0.fireDate.hour == 9 && $0.fireDate.minute == 0 })
    }

    @Test func fireTimeAtOrBeforeNowIsSkipped() {
        let milk = item("Milk", expires: 2026, 9, 25)

        let afterNine = ExpirationReminders.plan(for: [milk], now: date(2026, 9, 25, 10, 0), calendar: calendar)
        #expect(afterNine.isEmpty)

        // Exactly 9:00 counts as "already fired".
        let atNine = ExpirationReminders.plan(for: [milk], now: date(2026, 9, 25, 9, 0), calendar: calendar)
        #expect(atNine.isEmpty)

        // Past 9:00 the day before: only the expiry day remains.
        let dayBefore = ExpirationReminders.plan(for: [milk], now: date(2026, 9, 24, 21, 30), calendar: calendar)
        #expect(dayBefore.map(ymd) == [[2026, 9, 25]])
        #expect(dayBefore.first?.title == "Milk expires today")
    }

    @Test func severalItemsOnOneDayMakeOneDigest() {
        let now = date(2026, 9, 22, 7, 0)
        // Deliberately unsorted input; "today" is 2026-09-22.
        let items = [
            item("Yogurt", expires: 2026, 9, 25),  // 3 days left
            item("Milk", expires: 2026, 9, 22),    // today
            item("Eggs", expires: 2026, 9, 23),    // tomorrow
            item("Apples", expires: 2026, 9, 24),  // 2 days left
            item("Bread", expires: 2026, 9, 22),   // today (ties with Milk; name decides)
        ]
        let plan = ExpirationReminders.plan(for: items, now: now, calendar: calendar)

        let today = plan.first
        #expect(today.map(ymd) == [2026, 9, 22])
        #expect(today?.title == "5 items need attention")
        #expect(today?.body == "Bread expires today · Milk expires today · Eggs expires tomorrow · and 2 more")

        // Exactly one reminder per day, sorted by fire date.
        let days = plan.map(ymd)
        #expect(days == [[2026, 9, 22], [2026, 9, 23], [2026, 9, 24], [2026, 9, 25]])

        // Day 2026-09-24: Apples today, Yogurt 1 day, Eggs gone.
        #expect(plan[2].title == "2 items need attention")
        #expect(plan[2].body == "Apples expires today · Yogurt expires tomorrow")

        // Input order doesn't change the result.
        #expect(ExpirationReminders.plan(for: items.reversed(), now: now, calendar: calendar) == plan)
    }

    @Test func multiItemBodyUsesInDaysWording() {
        let now = date(2026, 9, 22, 7, 0)
        let plan = ExpirationReminders.plan(
            for: [item("Cheese", expires: 2026, 9, 25), item("Ham", expires: 2026, 9, 25)],
            now: now,
            calendar: calendar
        )
        #expect(plan.first?.title == "2 items need attention")
        #expect(plan.first?.body == "Cheese in 3 days · Ham in 3 days")
    }

    @Test func totalIsCappedAtMaxCount() {
        let now = date(2026, 9, 22, 7, 0)
        // One item expiring on each of the next 30 days -> 30 distinct reminder days.
        let items = (0..<30).map { offset in
            ReminderItem(name: "Item \(offset)", expirationDate: calendar.date(byAdding: .day, value: offset, to: date(2026, 9, 22))!)
        }
        #expect(ExpirationReminders.plan(for: items, now: now, calendar: calendar).count == 30)

        let capped = ExpirationReminders.plan(for: items, now: now, calendar: calendar, maxCount: 5)
        #expect(capped.count == 5)
        // The cap keeps the soonest days.
        #expect(capped.map(ymd) == [[2026, 9, 22], [2026, 9, 23], [2026, 9, 24], [2026, 9, 25], [2026, 9, 26]])

        #expect(ExpirationReminders.plan(for: items, now: now, calendar: calendar, maxCount: 0).isEmpty)
    }

    @Test func planningStopsSixtyDaysOut() {
        let now = date(2026, 9, 22, 7, 0)
        // 2026-11-22 is 61 days after 2026-09-22: the 3/2/1-day reminders
        // (days 58, 59, 60) fit in the window; the expiry day itself (61) doesn't.
        let plan = ExpirationReminders.plan(for: [item("Rice", expires: 2026, 11, 22)], now: now, calendar: calendar)
        #expect(plan.map(ymd) == [[2026, 11, 19], [2026, 11, 20], [2026, 11, 21]])

        let farAway = ExpirationReminders.plan(for: [item("Honey", expires: 2027, 6, 1)], now: now, calendar: calendar)
        #expect(farAway.isEmpty)
    }

    @Test func pastItemsAreIgnored() {
        let now = date(2026, 9, 22, 7, 0)
        let expired = [item("Old milk", expires: 2026, 9, 20), item("Older bread", expires: 2026, 8, 1)]
        #expect(ExpirationReminders.plan(for: expired, now: now, calendar: calendar).isEmpty)

        // An expired item doesn't leak into a live item's digest.
        let mixed = expired + [item("Eggs", expires: 2026, 9, 23)]
        let plan = ExpirationReminders.plan(for: mixed, now: now, calendar: calendar)
        #expect(plan.map(\.title) == ["Eggs expires tomorrow", "Eggs expires today"])
    }

    @Test func daylightSavingWeekKeepsDaysAndNineAM() {
        // US clocks fall back at 2:00 on 2026-11-01, so that day is 25 hours long.
        let now = date(2026, 10, 29, 20, 0)
        let plan = ExpirationReminders.plan(for: [item("Soup", expires: 2026, 11, 2)], now: now, calendar: calendar)

        #expect(plan.map(ymd) == [[2026, 10, 30], [2026, 10, 31], [2026, 11, 1], [2026, 11, 2]])
        #expect(plan.map(\.title) == ["Soup: 3 days left", "Soup: 2 days left", "Soup expires tomorrow", "Soup expires today"])

        for reminder in plan {
            #expect(reminder.fireDate.hour == 9)
            #expect(reminder.fireDate.minute == 0)
            // Resolved in local time, every reminder lands on 9:00 wall-clock, EDT or EST.
            let fire = calendar.date(from: reminder.fireDate)!
            let local = calendar.dateComponents([.hour, .minute], from: fire)
            #expect(local.hour == 9 && local.minute == 0)
        }
    }

    @Test func identifierIsPrefixPlusZeroPaddedDate() {
        let now = date(2026, 9, 30, 7, 0)
        let plan = ExpirationReminders.plan(for: [item("Tofu", expires: 2026, 10, 3)], now: now, calendar: calendar)

        #expect(plan.map(\.identifier) == [
            "pantryping.reminder.2026-09-30",
            "pantryping.reminder.2026-10-01",
            "pantryping.reminder.2026-10-02",
            "pantryping.reminder.2026-10-03",
        ])
        #expect(plan.allSatisfy { $0.identifier.hasPrefix(ExpirationReminders.identifierPrefix) })
    }

    @Test func customHourIsUsed() {
        let now = date(2026, 9, 22, 7, 0)
        let plan = ExpirationReminders.plan(for: [item("Milk", expires: 2026, 9, 22)], now: now, calendar: calendar, hour: 18)
        #expect(plan.count == 1)
        #expect(plan.first?.fireDate == DateComponents(year: 2026, month: 9, day: 22, hour: 18, minute: 0))
    }
}
