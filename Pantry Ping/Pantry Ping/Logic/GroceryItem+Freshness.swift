//
//  GroceryItem+Freshness.swift
//  Pantry Ping
//

import Foundation

// Business logic for a grocery: countdowns, display text, sorting, and state changes.
// Kept out of the views so it can be unit tested and reused by every screen.
extension GroceryItem {
    func daysRemaining(now: Date, calendar: Calendar = .current) -> Int? {
        ExpirationStatus.daysRemaining(until: expirationDate, now: now, calendar: calendar)
    }

    func expirationStatus(now: Date, calendar: Calendar = .current) -> ExpirationStatus {
        ExpirationStatus(daysRemaining: daysRemaining(now: now, calendar: calendar))
    }

    // The one line that answers "how is this item doing?"
    // With a date: "Expires tomorrow". Without one: what we know instead, e.g. "Frozen 4 days ago".
    func freshnessText(now: Date, calendar: Calendar = .current) -> String {
        if let days = daysRemaining(now: now, calendar: calendar) {
            return ExpirationStatus.label(daysRemaining: days, isSuggested: expirationSource == .suggested)
        }
        if let stateDate = dateOfCurrentState {
            let text = "\(foodState.displayName) \(GroceryItem.relativeDayText(from: stateDate, now: now, calendar: calendar))"
            // A gentle quality reminder for long-frozen food — a UI threshold, not a safety rule.
            let daysInState = -(ExpirationStatus.daysRemaining(until: stateDate, now: now, calendar: calendar) ?? 0)
            return foodState == .frozen && daysInState >= 90 ? text + " · check quality" : text
        }
        let added = "No date · Added \(GroceryItem.relativeDayText(from: dateAdded, now: now, calendar: calendar))"
        // Food bought frozen gets the same gentle quality reminder after 90 days.
        let daysSinceAdded = -(ExpirationStatus.daysRemaining(until: dateAdded, now: now, calendar: calendar) ?? 0)
        return storageLocation == .freezer && daysSinceAdded >= 90 ? added + " · check quality" : added
    }

    // Leftovers, thawed food, and suggested (guidance) dates can't be judged by look and
    // smell once past, so they get stricter wording than an ordinary package date.
    var isPastDateRisky: Bool {
        foodState == .cooked || foodState == .thawed || expirationSource == .suggested
    }

    var pastDateGuidance: String {
        isPastDateRisky ? FoodState.expiredLeftoverGuidance : FoodState.expiredGuidance
    }

    // Opened, cooked, or thawed food with no use-by date deserves a gentle nudge:
    // those are the states where timing matters most.
    var shouldSuggestUseByDate: Bool {
        expirationDate == nil && [.opened, .cooked, .thawed].contains(foodState)
    }

    // When the item entered its current food state (nil for fresh items).
    var dateOfCurrentState: Date? {
        switch foodState {
        case .fresh: nil
        case .opened: dateOpened
        case .cooked: dateCooked
        case .frozen: dateFrozen
        case .thawed: dateThawed
        }
    }

    // "today", "yesterday", "4 days ago", "3 weeks ago".
    static func relativeDayText(from date: Date, now: Date, calendar: Calendar = .current) -> String {
        let daysAgo = -(ExpirationStatus.daysRemaining(until: date, now: now, calendar: calendar) ?? 0)
        switch daysAgo {
        case ..<1: return "today"
        case 1: return "yesterday"
        case 2...13: return "\(daysAgo) days ago"
        default:
            let weeks = daysAgo / 7
            return weeks < 9 ? "\(weeks) weeks ago" : "\(daysAgo / 30) months ago"
        }
    }

    // Most urgent first: soonest date first, then items with no date,
    // and ties broken by whichever was added earliest (older food rises to the top).
    static func sortedByUrgency(_ items: [GroceryItem], now: Date, calendar: Calendar = .current) -> [GroceryItem] {
        items.sorted { first, second in
            let firstDays = first.daysRemaining(now: now, calendar: calendar)
            let secondDays = second.daysRemaining(now: now, calendar: calendar)
            switch (firstDays, secondDays) {
            case let (a?, b?) where a != b:
                return a < b
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none) where first.shouldSuggestUseByDate != second.shouldSuggestUseByDate:
                // Undated items that need a date float above ordinary undated items.
                return first.shouldSuggestUseByDate
            default:
                return first.dateAdded < second.dateAdded
            }
        }
    }

    // MARK: - Actions

    // Moves the food to a new state (e.g. Freeze), records when it happened in the history,
    // and sets the use-by date the user chose on the state-change sheet (possibly nil).
    // The original package date is never touched.
    func changeFoodState(to newState: FoodState, newExpirationDate: Date?, source: ExpirationSource = .entered, on date: Date = .now) {
        foodState = newState
        switch newState {
        case .fresh: break
        case .opened: dateOpened = date
        case .cooked: dateCooked = date
        case .frozen: dateFrozen = date
        case .thawed: dateThawed = date
        }
        var detail: [String] = []
        if let location = newState.impliedLocation, location != storageLocation {
            detail.append("Moved to \(location.displayName)")
            storageLocation = location
        }
        expirationDate = newExpirationDate.map { GroceryItem.calendarDay($0) }
        expirationSource = expirationDate == nil ? .entered : source
        if let expirationDate {
            let prefix = expirationSource == .suggested ? "Suggested use by" : "Use by"
            detail.append("\(prefix) \(expirationDate.formatted(date: .abbreviated, time: .omitted))")
        }
        if let kind = FoodEventKind(rawValue: newState.rawValue) {
            addEvent(kind, date: date, detail: detail.joined(separator: " · "))
        }
    }

    // Sets the current use-by date.
    // `isCorrection` is true when the user is fixing what they typed (the edit form): for a
    // still-fresh item the original date is corrected too. It's false when plans changed
    // (e.g. "Still have it"), so the original package date is preserved.
    func setUseByDate(_ date: Date?, isCorrection: Bool, source: ExpirationSource = .entered) {
        let day = date.map { GroceryItem.calendarDay($0) }
        let old = expirationDate
        expirationDate = day
        expirationSource = day == nil ? .entered : source
        // Only while the original still matches the current date: once a date was changed
        // on purpose (e.g. "Still have it"), the original package date must stay put.
        if isCorrection && foodState == .fresh && originalExpirationDate == old {
            originalExpirationDate = day
        }
        if old != day {
            let text = day.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "No date"
            addEvent(.dateChanged, detail: source == .suggested ? "\(text) (suggested)" : text)
        }
    }
}
