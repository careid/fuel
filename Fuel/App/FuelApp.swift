import SwiftUI
import SwiftData

@main
struct FuelApp: App {
    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Schema(FuelSchemaV1.models),
                migrationPlan: FuelMigrationPlan.self
            )
        } catch {
            fatalError("Failed to create model container: \(error)")
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
