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

    init(
        calorieTarget: Int = 2200,
        proteinTarget: Int = 160,
        carbsTarget: Int = 250,
        fatTarget: Int = 70,
        apiKey: String = Secrets.anthropicAPIKey
    ) {
        self.calorieTarget = calorieTarget
        self.proteinTarget = proteinTarget
        self.carbsTarget = carbsTarget
        self.fatTarget = fatTarget
        self.apiKey = apiKey
    }
}
