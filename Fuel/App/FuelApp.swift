import SwiftUI
import SwiftData

@main
struct FuelApp: App {
    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer

    init() {
        let schema = Schema(FuelSchemaV4.models)

        // Primary: CloudKit-backed store — data lives in iCloud and survives
        // app deletion / reinstall / device restore.
        let ckConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        if let c = try? ModelContainer(for: schema, configurations: [ckConfig]) {
            container = c
            return
        }

        // Fallback: local-only store (simulator, no iCloud account, etc.).
        // Uses an explicit name so it never collides with legacy default.store files.
        NSLog("[Fuel] CloudKit unavailable, using local store")
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let storeURL = appSupport.appendingPathComponent("fuel.store")
        let localConfig = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)

        if let c = try? ModelContainer(for: schema, configurations: [localConfig]) {
            container = c
            return
        }

        // Local store is corrupted or schema-incompatible. Since this is the
        // non-CloudKit fallback path, there is no user data to preserve here —
        // wipe and recreate.
        NSLog("[Fuel] Local store failed to open, wiping and recreating")
        let base = storeURL.deletingPathExtension()
        for ext in ["store", "store-wal", "store-shm"] {
            try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
        }

        container = try! ModelContainer(for: schema, configurations: [localConfig])
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
