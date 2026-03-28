import SwiftUI
import SwiftData

@main
struct FuelApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            DayLog.self,
            Meal.self,
            FoodItem.self,
            UserSettings.self,
            HealthSnapshot.self,
        ])
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await ReminderManager.shared.requestPermissions() }
            }
        }
    }
}
