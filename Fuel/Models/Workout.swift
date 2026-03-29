import Foundation
import SwiftData

@Model
final class Workout {
    var id: UUID
    var timestamp: Date
    var workoutCategory: WorkoutCategory
    var durationMinutes: Int
    var caloriesBurned: Int?
    var notes: String?

    @Relationship(inverse: \DayLog.workouts)
    var dayLog: DayLog?

    init(
        timestamp: Date = .now,
        category: WorkoutCategory,
        durationMinutes: Int,
        caloriesBurned: Int? = nil,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.workoutCategory = category
        self.durationMinutes = durationMinutes
        self.caloriesBurned = caloriesBurned
        self.notes = notes
    }
}

enum WorkoutCategory: String, Codable, CaseIterable {
    case running  = "Running"
    case cycling  = "Cycling"
    case swimming = "Swimming"
    case strength = "Strength"
    case hiit     = "HIIT"
    case yoga     = "Yoga"
    case walking  = "Walking"
    case other    = "Other"

    var icon: String {
        switch self {
        case .running:  "figure.run"
        case .cycling:  "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .strength: "dumbbell.fill"
        case .hiit:     "bolt.fill"
        case .yoga:     "figure.yoga"
        case .walking:  "figure.walk"
        case .other:    "figure.mixed.cardio"
        }
    }

    var label: String { rawValue }
}
