import SwiftUI
import SwiftData

@main
struct FuelApp: App {
    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer

    init() {
        let schema = Schema(FuelSchemaV4.models)
        let cloudConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)

        // Prefer CloudKit-backed store so data survives app deletion and syncs across devices.
        // Falls back to local-only if CloudKit isn't available (simulator, no iCloud sign-in, etc.).
        if let c = try? ModelContainer(for: schema, configurations: cloudConfig) {
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
