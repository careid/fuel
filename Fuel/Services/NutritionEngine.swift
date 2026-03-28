import Foundation
import SwiftData

@MainActor
final class NutritionEngine {
    private let modelContext: ModelContext
    private let claudeService = ClaudeService()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Day Log Management

    func dayLogOrCreate(for date: Date) throws -> DayLog {
        let dateStr = DayLog.dateFormatter.string(from: date)
        let descriptor = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.dateString == dateStr }
        )
        let results = try modelContext.fetch(descriptor)
        if let existing = results.first { return existing }
        let newLog = DayLog(date: date)
        modelContext.insert(newLog)
        try modelContext.save()
        return newLog
    }

    func todayLog() throws -> DayLog {
        let todayStr = DayLog.todayString()
        let descriptor = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.dateString == todayStr }
        )
        let results = try modelContext.fetch(descriptor)

        if let existing = results.first {
            return existing
        }

        let newLog = DayLog()
        modelContext.insert(newLog)
        try modelContext.save()
        return newLog
    }

    func dayLog(for date: Date) throws -> DayLog? {
        let dateStr = DayLog.dateFormatter.string(from: date)
        let descriptor = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.dateString == dateStr }
        )
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Meal Logging

    func logMeal(
        text: String,
        mealType: MealType,
        apiKey: String
    ) async throws -> Meal {
        let extraction = try await claudeService.extractMeal(from: text, apiKey: apiKey)

        let foodItems = extraction.items.map { item in
            FoodItem(
                name: item.name,
                calories: item.calories,
                proteinGrams: item.proteinGrams,
                carbsGrams: item.carbsGrams,
                fatGrams: item.fatGrams,
                quantity: item.quantity,
                confidence: Confidence(rawValue: item.confidence) ?? .medium
            )
        }

        let meal = Meal(
            mealType: mealType,
            items: foodItems,
            inputType: .text,
            rawInputText: text
        )

        let log = try todayLog()
        log.meals.append(meal)
        try modelContext.save()

        return meal
    }

    func saveRawMeal(text: String, mealType: MealType, date: Date = .now, inputType: InputType = .text) throws -> Meal {
        let meal = Meal(timestamp: date, mealType: mealType, items: [], inputType: inputType, rawInputText: text)
        let log = try dayLogOrCreate(for: date)
        log.meals.append(meal)
        try modelContext.save()
        return meal
    }

    func processMeal(_ meal: Meal, apiKey: String) async throws {
        guard let text = meal.rawInputText, !text.isEmpty else { return }
        let extraction = try await claudeService.extractMeal(from: text, apiKey: apiKey)
        meal.items = extraction.items.map { item in
            FoodItem(
                name: item.name,
                calories: item.calories,
                proteinGrams: item.proteinGrams,
                carbsGrams: item.carbsGrams,
                fatGrams: item.fatGrams,
                quantity: item.quantity,
                confidence: Confidence(rawValue: item.confidence) ?? .medium
            )
        }
        try modelContext.save()
    }

    func refineMeal(
        _ meal: Meal,
        with refinement: String,
        apiKey: String
    ) async throws {
        let currentItems = meal.items.map { item in
            ExtractedItem(
                name: item.name,
                calories: item.calories,
                proteinGrams: item.proteinGrams,
                carbsGrams: item.carbsGrams,
                fatGrams: item.fatGrams,
                quantity: item.quantity,
                confidence: item.confidence.rawValue
            )
        }

        let extraction = try await claudeService.refineMeal(
            originalItems: currentItems,
            refinement: refinement,
            apiKey: apiKey
        )

        // Replace all items with updated extraction
        for item in meal.items {
            modelContext.delete(item)
        }

        meal.items = extraction.items.map { item in
            FoodItem(
                name: item.name,
                calories: item.calories,
                proteinGrams: item.proteinGrams,
                carbsGrams: item.carbsGrams,
                fatGrams: item.fatGrams,
                quantity: item.quantity,
                confidence: Confidence(rawValue: item.confidence) ?? .medium
            )
        }

        try modelContext.save()
    }

    // MARK: - Settings

    func settings() throws -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>()
        let results = try modelContext.fetch(descriptor)

        if let existing = results.first {
            if existing.apiKey.isEmpty {
                existing.apiKey = Secrets.anthropicAPIKey
                try modelContext.save()
            }
            return existing
        }

        let settings = UserSettings()
        modelContext.insert(settings)
        try modelContext.save()
        return settings
    }

    // MARK: - Deletion

    func deleteMeal(_ meal: Meal) throws {
        modelContext.delete(meal)
        try modelContext.save()
    }
}
