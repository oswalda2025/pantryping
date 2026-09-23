//
//  HouseholdType.swift
//  Pantry Ping
//

import Foundation

// Who the app is set up for, chosen during onboarding. These are presets on the same
// app — not separate modes — so every feature works for everyone.
// Raw values are saved, so they must never be renamed.
enum HouseholdType: String, CaseIterable, Identifiable {
    case student
    case solo
    case household

    var id: String { rawValue }

    var title: String {
        switch self {
        case .student: "Student"
        case .solo: "Living alone"
        case .household: "Family or household"
        }
    }

    var subtitle: String {
        switch self {
        case .student: "Simple inventory, quick meals, and keeping grocery costs down."
        case .solo: "Meal prep, nutrition, and wasting less when cooking for one."
        case .household: "Bigger shops, shared groceries, and keeping everyone organized."
        }
    }

    var systemImage: String {
        switch self {
        case .student: "graduationcap.fill"
        case .solo: "person.fill"
        case .household: "house.fill"
        }
    }

    // Tips shown after choosing, pointing to features that suit this household.
    var tips: [String] {
        switch self {
        case .student:
            ["Add prices when you buy — History shows what you spend each day.",
             "Try Meals: cook once, eat for days, and log each portion."]
        case .solo:
            ["Use Some logs what you eat, with calories and macros when you add them.",
             "Freeze half a pack when it's too much for one — the app tracks it."]
        case .household:
            ["The Shopping list turns straight into purchases when you get home.",
             "Buy Again reuses a product's details, so big shops are quick to add."]
        }
    }
}

// The keys for the on-device profile, in one place so they can't be mistyped.
// The profile lives in UserDefaults (via @AppStorage) — on this device only.
enum ProfileKeys {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let name = "userName"
    static let householdType = "householdType"
}
