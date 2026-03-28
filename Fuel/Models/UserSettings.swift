import Foundation
import SwiftData
import CoreLocation

@Model
final class UserSettings {
    var calorieTarget: Int
    var proteinTarget: Int
    var carbsTarget: Int
    var fatTarget: Int
    var apiKey: String

    // Reminders
    var remindersEnabled: Bool
    var geofenceEnabled: Bool
    var kitchenLatitude: Double   // 0 = not configured
    var kitchenLongitude: Double  // 0 = not configured

    var hasKitchenLocation: Bool { kitchenLatitude != 0 || kitchenLongitude != 0 }
    var kitchenCoordinate: CLLocationCoordinate2D? {
        guard hasKitchenLocation else { return nil }
        return CLLocationCoordinate2D(latitude: kitchenLatitude, longitude: kitchenLongitude)
    }

    init(
        calorieTarget: Int = 2200,
        proteinTarget: Int = 160,
        carbsTarget: Int = 250,
        fatTarget: Int = 70,
        apiKey: String = Secrets.anthropicAPIKey,
        remindersEnabled: Bool = true,
        geofenceEnabled: Bool = true,
        kitchenLatitude: Double = 0,
        kitchenLongitude: Double = 0
    ) {
        self.calorieTarget = calorieTarget
        self.proteinTarget = proteinTarget
        self.carbsTarget = carbsTarget
        self.fatTarget = fatTarget
        self.apiKey = apiKey
        self.remindersEnabled = remindersEnabled
        self.geofenceEnabled = geofenceEnabled
        self.kitchenLatitude = kitchenLatitude
        self.kitchenLongitude = kitchenLongitude
    }
}
