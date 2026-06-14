// xcode: set sdk=iOS

import SwiftUI
import SwiftData

@main
struct VoiceHealthJournalApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: JournalEntry.self, SymptomLog.self, LifestyleLog.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        AnalyticsLogger.shared.log(.appLaunched)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            TimelineView()
                .tabItem { Label("Journal", systemImage: "book.closed") }
            CheckInView()
                .tabItem { Label("Check-in", systemImage: "mic.circle.fill") }
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(DS.Colors.accent)
    }
}
