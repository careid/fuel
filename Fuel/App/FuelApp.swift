import SwiftUI
import SwiftData

@main
struct FuelApp: App {
    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer

    init() {
        let schema = Schema(FuelSchemaV3.models)
        // Try versioned migration first; fall back to simple open if the existing
        // store pre-dates the migration plan (no version metadata in the store yet).
        if let c = try? ModelContainer(for: schema, migrationPlan: FuelMigrationPlan.self) {
            container = c
        } else if let c = try? ModelContainer(for: schema) {
            container = c
        } else {
            fatalError("Cannot open or create the SwiftData store.")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await ReminderManager.shared.requestPermissions() }
            }
        }
    }
}
