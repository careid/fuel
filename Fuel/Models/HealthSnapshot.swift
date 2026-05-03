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

    // The actual measurement timestamp from HealthKit, so we can tell a fresh
    // weight from one carried over from days ago (most days the user doesn't weigh in).
    var weightMeasuredAt: Date?

    // True when activeCalories was filled in from a step-based estimate because
    // the user wasn't wearing their watch and HealthKit returned little/no data.
    var activeCaloriesEstimated: Bool = false

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
