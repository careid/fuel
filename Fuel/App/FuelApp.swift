import SwiftUI
import SwiftData

@main
struct FuelApp: App {
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
    }
}
