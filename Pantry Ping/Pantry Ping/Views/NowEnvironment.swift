//
//  NowEnvironment.swift
//  Pantry Ping
//

import SwiftUI

// A shared "current time" that every screen reads with `@Environment(\.now)`.
// SwiftUI only redraws when data changes, and midnight isn't a data change — so the root
// view refreshes this value when the app reopens or the day rolls over, and every
// "3 days left" label updates together. Views never call `Date()` for display logic.
extension EnvironmentValues {
    // @Entry declares a new environment value with a default.
    @Entry var now: Date = .now
}
