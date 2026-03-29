import Foundation
import SwiftData

@Model
final class DailyBrief {
    var dateString: String        // yyyy-MM-dd — one per calendar day
    var brief: String             // 2–4 sentence coaching text from Claude
    var patternAlert: String?     // Optional cross-dataset insight
    var recommendedCalories: Int? // Optional target nudge for today
    var recommendedProtein: Int?
    var generatedAt: Date

    init(
        dateString: String,
        brief: String,
        patternAlert: String? = nil,
        recommendedCalories: Int? = nil,
        recommendedProtein: Int? = nil
    ) {
        self.dateString = dateString
        self.brief = brief
        self.patternAlert = patternAlert
        self.recommendedCalories = recommendedCalories
        self.recommendedProtein = recommendedProtein
        self.generatedAt = .now
    }
}
