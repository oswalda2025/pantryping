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
        let arguments = ProcessInfo.processInfo.arguments
        // UI tests pass "-resetProfile" to see the first-launch welcome screens again.
        if arguments.contains("-resetProfile") {
            for key in [ProfileKeys.hasCompletedOnboarding, ProfileKeys.name, ProfileKeys.householdType] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        modelContainer = DatabaseLoader.makeContainer(arguments: arguments)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Makes the database available to every view via @Query and @Environment(\.modelContext).
        .modelContainer(modelContainer)
    }
}

// Opens the database, upgrading older versions through the migration plan.
// If a saved database can't be opened at all, the app must not crash on every launch:
// the unreadable file is moved aside (never deleted) and the app starts fresh, then
// explains what happened on the next screen.
enum DatabaseLoader {
    static let recoveryNoteKey = "databaseRecoveryNote"

    static func makeContainer(arguments: [String]) -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration: ModelConfiguration
        if arguments.contains("-uiTesting") {
            // Automated UI tests start from an empty, throwaway in-memory database.
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else if arguments.contains("-uiTestingDiskStore") {
            // Restart tests need a real file that survives relaunching, kept apart from real data.
            let url = URL.temporaryDirectory.appending(path: "PantryPingUITest.store")
            if arguments.contains("-resetStore") {
                for suffix in ["", "-wal", "-shm"] {
                    try? FileManager.default.removeItem(atPath: url.path + suffix)
                }
            }
            configuration = ModelConfiguration(url: url)
        } else {
            configuration = ModelConfiguration()
        }
        return openOrRecover(schema: schema, configuration: configuration)
    }

    // Separate so tests can point it at a deliberately broken file.
    static func openOrRecover(schema: Schema, configuration: ModelConfiguration) -> ModelContainer {
        // `do`/`catch` handles code that can fail (`try`).
        do {
            return try ModelContainer(for: schema, migrationPlan: PantryPingMigrationPlan.self,
                                      configurations: configuration)
        } catch {
            let backupName = moveAside(storeAt: configuration.url)
            UserDefaults.standard.set(
                "Pantry Ping couldn't read its saved data, so it started fresh. The old data was kept in a backup file (\(backupName ?? "unavailable")) and has not been deleted.",
                forKey: recoveryNoteKey
            )
            do {
                return try ModelContainer(for: schema, migrationPlan: PantryPingMigrationPlan.self,
                                          configurations: configuration)
            } catch {
                // Even a brand-new database failed (e.g. the device is out of storage).
                fatalError("Could not create the Pantry Ping database: \(error)")
            }
        }
    }

    // Renames the store and its companion files (-wal, -shm) to "…-unreadable-<time>".
    private static func moveAside(storeAt url: URL) -> String? {
        let stamp = Int(Date.now.timeIntervalSince1970)
        let fileManager = FileManager.default
        var backupName: String?
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: url.path + "-unreadable-\(stamp)" + suffix)
            try? fileManager.moveItem(at: source, to: destination)
            if suffix.isEmpty { backupName = destination.lastPathComponent }
        }
        return backupName
    }
}
