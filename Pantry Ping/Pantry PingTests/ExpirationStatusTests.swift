//
//  ExpirationStatusTests.swift
//  Pantry PingTests
//

import Foundation
import Testing
@testable import Pantry_Ping

// Every test uses a fixed calendar and time zone so results never depend on the machine.
@MainActor
struct ExpirationStatusTests {
    let newYork = TestDates.calendar(timeZone: "America/New_York")

    @Test(arguments: zip(
        [-20, -1, 0, 1, 2, 3, 4, 30],
        [ExpirationStatus.expired, .expired, .urgent, .urgent, .useSoon, .useSoon, .fresh, .fresh]
    ))
    func thresholds(days: Int, expected: ExpirationStatus) {
        #expect(ExpirationStatus(daysRemaining: days) == expected)
    }

    @Test func missingDateIsNoDate() {
        #expect(ExpirationStatus(daysRemaining: nil) == .noDate)
        #expect(ExpirationStatus.daysRemaining(until: nil, now: .now, calendar: newYork) == nil)
    }

    @Test(arguments: zip(
        [-30, -14, -13, -4, -1, 0, 1, 2, 10],
        ["Expired 2+ weeks ago", "Expired 2+ weeks ago", "Expired 13 days ago", "Expired 4 days ago",
         "Expired yesterday", "Expires today", "Expires tomorrow", "2 days left", "10 days left"]
    ))
    func labels(days: Int, expected: String) {
        #expect(ExpirationStatus.label(daysRemaining: days) == expected)
    }

    @Test func oneMinuteBeforeMidnightCountsTomorrowAsOneDay() {
        let now = TestDates.date(2026, 3, 1, hour: 23, minute: 59, in: newYork)
        let expiry = TestDates.date(2026, 3, 2, hour: 0, minute: 1, in: newYork)
        #expect(ExpirationStatus.daysRemaining(until: expiry, now: now, calendar: newYork) == 1)
    }

    @Test func sameDayLateTimeIsStillToday() {
        let now = TestDates.date(2026, 3, 2, hour: 0, minute: 1, in: newYork)
        let expiry = TestDates.date(2026, 3, 2, hour: 23, minute: 59, in: newYork)
        #expect(ExpirationStatus.daysRemaining(until: expiry, now: now, calendar: newYork) == 0)
    }

    // A 23- or 25-hour day must still count as one day.
    @Test func daylightSavingChangesDoNotShiftTheCount() {
        let springNow = TestDates.date(2026, 3, 7, in: newYork)
        let springExpiry = TestDates.date(2026, 3, 9, in: newYork)
        #expect(ExpirationStatus.daysRemaining(until: springExpiry, now: springNow, calendar: newYork) == 2)

        let fallNow = TestDates.date(2026, 10, 31, in: newYork)
        let fallExpiry = TestDates.date(2026, 11, 2, in: newYork)
        #expect(ExpirationStatus.daysRemaining(until: fallExpiry, now: fallNow, calendar: newYork) == 2)
    }

    // Dates are stored at noon, so a trip of up to ±10 hours keeps the same calendar day.
    @Test func noonStorageSurvivesTimeZoneTravel() {
        let home = TestDates.calendar(secondsFromGMT: 0)
        let stored = GroceryItem.calendarDay(TestDates.date(2026, 5, 10, hour: 0, minute: 0, in: home), calendar: home)

        for offsetHours in [-10, 10] {
            let away = TestDates.calendar(secondsFromGMT: offsetHours * 3600)
            #expect(away.component(.day, from: stored) == 10)
        }
    }
}

// Small helpers for building exact dates in tests.
enum TestDates {
    static func calendar(timeZone identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    static func calendar(secondsFromGMT: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: secondsFromGMT)!
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
