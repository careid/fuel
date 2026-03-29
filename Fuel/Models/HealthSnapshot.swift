import Foundation
import SwiftData

@Model
final class HealthSnapshot {
    var dateString: String
    var steps: Int?
    var activeCalories: Int?
    var weightKg: Double?
    var restingHeartRate: Double?
    var sleepSeconds: Int?
    var workoutType: String?
    var workoutMinutes: Int?
    var workoutCalories: Int?

    var sleepHours: Double? { sleepSeconds.map { Double($0) / 3600.0 } }
    var weightLbs: Double?  { weightKg.map { $0 * 2.20462 } }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    init(date: Date = .now) {
        self.dateString = Self.dateFormatter.string(from: date)
    }
}
