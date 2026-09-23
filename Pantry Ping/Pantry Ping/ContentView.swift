//
//  ContentView.swift
//  Pantry Ping
//

import SwiftUI
import SwiftData

// The root of the app: three tabs, plus the app-wide "now" clock.
struct ContentView: View {
    // @State lets this view own a value; changing it redraws everything that reads it.
    @State private var now = Date.now

    // @Environment reads values the system provides — here, whether the app is on screen.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // `Tab` is the iOS 18 way to declare tab bar items.
        TabView {
            Tab("Kitchen", systemImage: "refrigerator") {
                HomeView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath") {
                HistoryView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .environment(\.now, now)
        // Refresh "now" whenever the app comes back to the foreground...
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                now = .now
            }
        }
        // ...and at midnight or after a time-zone change while it stays open.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = .now
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(SampleData.previewContainer)
}
