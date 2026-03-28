import Foundation
import SwiftData

@Model
final class Meal {
    var id: UUID
    var timestamp: Date
    var mealType: MealType
    @Relationship(deleteRule: .cascade)
    var items: [FoodItem]
    var inputType: InputType
    var rawInputText: String?

    @Relationship(inverse: \DayLog.meals)
    var dayLog: DayLog?

    var totalCalories: Int {
        items.reduce(0) { $0 + $1.calories }
    }

    var totalProtein: Double {
        items.reduce(0) { $0 + $1.proteinGrams }
    }

    var totalCarbs: Double {
        items.reduce(0) { $0 + $1.carbsGrams }
    }

    var totalFat: Double {
        items.reduce(0) { $0 + $1.fatGrams }
    }

    var isProcessed: Bool {
        !items.isEmpty
    }

    init(
        timestamp: Date = .now,
        mealType: MealType,
        items: [FoodItem] = [],
        inputType: InputType = .text,
        rawInputText: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.mealType = mealType
        self.items = items
        self.inputType = inputType
        self.rawInputText = rawInputText
    }
}

enum MealType: String, Codable, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snack

    var icon: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.fill"
        case .snack: "leaf.fill"
        }
    }

    var label: String {
        rawValue.capitalized
    }
}

enum InputType: String, Codable {
    case text
    case photo
    case voice
    case video
    case quickAdd
}
