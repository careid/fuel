import Foundation
import SwiftData

@Model
final class FoodItem {
    var id: UUID
    var name: String
    var calories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var quantity: String
    var confidence: Confidence

    @Relationship(inverse: \Meal.items)
    var meal: Meal?

    init(
        name: String,
        calories: Int,
        proteinGrams: Double,
        carbsGrams: Double,
        fatGrams: Double,
        quantity: String,
        confidence: Confidence = .medium
    ) {
        self.id = UUID()
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.quantity = quantity
        self.confidence = confidence
    }
}

enum Confidence: String, Codable {
    case high
    case medium
    case low
}
