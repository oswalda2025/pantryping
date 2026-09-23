//
//  GroceryCategory.swift
//  Pantry Ping
//

import Foundation

// Raw values are stable identifiers saved to disk; `displayName` is the text users see.
// Keeping them separate means we can reword a label without breaking saved data.
enum GroceryCategory: String, CaseIterable, Identifiable {
    case produce
    case dairyEggs
    case meatSeafood
    case bakery
    case dryCanned
    case beverages
    case snacks
    case condimentsSauces
    case leftovers
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .produce: "Produce"
        case .dairyEggs: "Dairy & Eggs"
        case .meatSeafood: "Meat & Seafood"
        case .bakery: "Bakery"
        case .dryCanned: "Dry & Canned Goods"
        case .beverages: "Beverages"
        case .snacks: "Snacks"
        case .condimentsSauces: "Condiments & Sauces"
        case .leftovers: "Leftovers"
        case .other: "Other"
        }
    }
}
