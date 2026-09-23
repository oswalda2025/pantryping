//
//  Pantry_PingApp.swift
//  Pantry Ping
//
//  Created by Dhiren Oswal on 22/09/26.
//

import SwiftUI
import SwiftData

@main
struct Pantry_PingApp: App {
    // The ModelContainer is the app's on-device database. It's created once at launch
    // and shared with every screen below.
    let modelContainer: ModelContainer

    init() {
        // `do`/`catch` handles code that can fail (`try`).
        do {
            modelContainer = try ModelContainer(
                for: Schema(versionedSchema: SchemaV1.self),
                migrationPlan: PantryPingMigrationPlan.self
            )
        } catch {
            // Without a database the app can't work, so stop with a clear message.
            // During development this usually means saved data no longer matches the model:
            // delete the app from the Simulator and run again.
            fatalError("Could not open the Pantry Ping database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Makes the database available to every view via @Query and @Environment(\.modelContext).
        .modelContainer(modelContainer)
    }
}
