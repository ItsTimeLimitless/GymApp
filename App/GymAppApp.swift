import SwiftUI

@main
struct GymAppApp: App {
    // Opens/creates the local SQLite DB and runs the schema once at launch.
    let database = Database.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(HealthKitManager.shared)
        }
    }
}
