//
//  ExpirationStatus.swift
//  Pantry Ping
//

import SwiftUI

// How urgently an item should be used. It's always calculated from a date and "now",
// never saved, so it can't go stale in the database.
// The Int raw value doubles as the sort order: most urgent first.
enum ExpirationStatus: Int, CaseIterable, Comparable {
    case expired
    case urgent
    case useSoon
    case fresh
    case noDate

    // Placeholder thresholds based on the user's own dates (not food-safety rules).
    init(daysRemaining: Int?) {
        // `guard let` unwraps the optional, or exits early if it's nil.
        guard let days = daysRemaining else {
            self = .noDate
            return
        }
        switch days {
        case ..<0: self = .expired
        case 0...1: self = .urgent
        case 2...3: self = .useSoon
        default: self = .fresh
        }
    }

    // Comparable lets us sort and compare statuses with `<`.
    static func < (lhs: ExpirationStatus, rhs: ExpirationStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // Whole calendar days from today until `date` (0 = today, -1 = yesterday).
    // Counting calendar days, not 24-hour blocks, keeps this correct across midnight
    // and daylight-saving changes. `now` and `calendar` are parameters so tests can fix them.
    static func daysRemaining(until date: Date?, now: Date, calendar: Calendar = .current) -> Int? {
        guard let date else { return nil }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: today, to: day).day
    }

    // Plain-language text so urgency never depends on color alone.
    static func label(daysRemaining days: Int) -> String {
        switch days {
        case ..<(-13): "Expired 2+ weeks ago"
        case -1: "Expired yesterday"
        case ..<0: "Expired \(-days) days ago"
        case 0: "Expires today"
        case 1: "Expires tomorrow"
        default: "\(days) days left"
        }
    }

    var sectionTitle: String {
        switch self {
        case .expired: "Expired"
        case .urgent: "Needs Attention"
        case .useSoon: "Use Soon"
        case .fresh: "Fresh"
        case .noDate: "No Date"
        }
    }

    var systemImage: String {
        switch self {
        case .expired: "xmark.octagon.fill"
        case .urgent: "exclamationmark.triangle.fill"
        case .useSoon: "clock.fill"
        case .fresh: "checkmark.circle.fill"
        case .noDate: "calendar"
        }
    }

    var tint: Color {
        switch self {
        case .expired: .red
        case .urgent: .orange
        case .useSoon: .yellow
        case .fresh: .green
        case .noDate: .secondary
        }
    }
}
