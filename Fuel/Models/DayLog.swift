import Foundation
import SwiftData

@Model
final class DayLog {
    var dateString: String
    @Relationship(deleteRule: .cascade)
    var meals: [Meal]
    @Relationship(deleteRule: .cascade)
    var workouts: [Workout]

    var totalCalories: Int {
        meals.reduce(0) { $0 + $1.totalCalories }
    }

    var totalProtein: Double {
        meals.reduce(0) { $0 + $1.totalProtein }
    }

    var totalCarbs: Double {
        meals.reduce(0) { $0 + $1.totalCarbs }
    }

    var totalFat: Double {
        meals.reduce(0) { $0 + $1.totalFat }
    }

    var date: Date {
        guard let parsed = Self.dateFormatter.date(from: dateString) else {
            assertionFailure("DayLog.date: malformed dateString '\(dateString)' — falling back to .now")
            return .now
        }
        return parsed
    }

    init(date: Date = .now) {
        self.dateString = Self.dateFormatter.string(from: date)
        self.meals = []
        self.workouts = []
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    static func todayString() -> String {
        dateFormatter.string(from: .now)
    }
}
