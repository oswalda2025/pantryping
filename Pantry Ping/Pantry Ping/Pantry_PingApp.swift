//
//  Pantry_PingApp.swift
//  Pantry Ping
//
//  Created by Dhiren Oswal on 22/09/26.
//

import SwiftUI
import SwiftData
import UserNotifications

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
        // Without a delegate, iOS hides a reminder that arrives while the app is open.
        UNUserNotificationCenter.current().delegate = ForegroundNotifications.shared
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
// If the saved database can't be opened (for example, a future update with a migration
// bug, or a full disk), the app must neither crash nor hide the user's data. It leaves the
// file exactly as it is, runs on a temporary in-memory database, and asks the user.
// A later fixed update will then open the untouched data normally.
enum DatabaseLoader {
    // Set when the saved database couldn't be opened this launch.
    private(set) static var failedStoreURL: URL?

    static func makeContainer(arguments: [String]) -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV3.self)
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
        failedStoreURL = nil
        // `do`/`catch` handles code that can fail (`try`).
        do {
            return try ModelContainer(for: schema, migrationPlan: PantryPingMigrationPlan.self,
                                      configurations: configuration)
        } catch {
            // Don't touch the file: the problem may be temporary or fixed by an update.
            failedStoreURL = configuration.url
            do {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            } catch {
                // Even an in-memory database failed, which means the app itself is broken.
                fatalError("Could not create the Pantry Ping database: \(error)")
            }
        }
    }

    // Only when the user chooses "Start Fresh": the unreadable file is renamed (never deleted),
    // so a brand-new database is created on the next launch. Returns the backup's file name.
    @discardableResult
    static func moveAsideForFreshStart() -> String? {
        guard let url = failedStoreURL else { return nil }
        return moveAside(storeAt: url)
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

// Shows the 9 AM reminder as a banner even when Pantry Ping is open at that moment.
// The delegate must stay alive, hence the shared instance.
final class ForegroundNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotifications()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
