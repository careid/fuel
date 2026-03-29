import Foundation
import SwiftData

final class CoachService {
    private let claude = ClaudeService()

    /// Returns a cached brief for today, or generates and caches a new one.
    func generateBriefIfNeeded(
        modelContext: ModelContext,
        settings: UserSettings
    ) async throws -> DailyBrief {
        let today = DayLog.dateFormatter.string(from: .now)

        // Return cached brief if one already exists for today
        var descriptor = FetchDescriptor<DailyBrief>(
            predicate: #Predicate { $0.dateString == today }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        // Build context from stored data
        let context = try buildContext(modelContext: modelContext, settings: settings)

        // Call Claude
        let result = try await claude.generateDailyBrief(context: context, apiKey: settings.apiKey)

        // Cache and return
        let brief = DailyBrief(
            dateString: today,
            brief: result.brief,
            patternAlert: result.patternAlert,
            recommendedCalories: result.recommendedCalories,
            recommendedProtein: result.recommendedProtein
        )
        modelContext.insert(brief)
        try? modelContext.save()
        return brief
    }

    // MARK: - Context Building

    private func buildContext(modelContext: ModelContext, settings: UserSettings) throws -> BriefContext {
        let cal = Calendar.current
        let today = Date.now
        let todayString = DayLog.dateFormatter.string(from: today)

        // Fetch last 14 DayLogs (excluding today — we want history)
        var logDescriptor = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.dateString < todayString },
            sortBy: [SortDescriptor(\DayLog.dateString, order: .reverse)]
        )
        logDescriptor.fetchLimit = 14
        let recentLogs = (try? modelContext.fetch(logDescriptor)) ?? []

        // Fetch last 14 HealthSnapshots (including yesterday)
        var snapDescriptor = FetchDescriptor<HealthSnapshot>(
            predicate: #Predicate { $0.dateString < todayString },
            sortBy: [SortDescriptor(\HealthSnapshot.dateString, order: .reverse)]
        )
        snapDescriptor.fetchLimit = 14
        let recentSnaps = (try? modelContext.fetch(snapDescriptor)) ?? []

        // Yesterday's data
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let yesterdayString = DayLog.dateFormatter.string(from: yesterday)
        let yesterdayLog = recentLogs.first { $0.dateString == yesterdayString }
        let yesterdaySnap = recentSnaps.first { $0.dateString == yesterdayString }

        // 14-day averages
        let logsWithMeals = recentLogs.filter { !$0.meals.isEmpty }
        let avgCalories = logsWithMeals.isEmpty ? 0 :
            Double(logsWithMeals.reduce(0) { $0 + $1.totalCalories }) / Double(logsWithMeals.count)
        let avgProtein = logsWithMeals.isEmpty ? 0 :
            logsWithMeals.reduce(0.0) { $0 + $1.totalProtein } / Double(logsWithMeals.count)

        let snapsWithSleep = recentSnaps.filter { $0.sleepHours != nil }
        let avgSleep: Double? = snapsWithSleep.isEmpty ? nil :
            snapsWithSleep.reduce(0.0) { $0 + ($1.sleepHours ?? 0) } / Double(snapsWithSleep.count)

        let loggingPct = recentLogs.isEmpty ? 0 :
            Int(Double(logsWithMeals.count) / Double(recentLogs.count) * 100)

        // Weight trend (simple linear: compare first half vs second half of window)
        let snapsWithWeight = recentSnaps.filter { $0.weightLbs != nil }
        let latestWeight = snapsWithWeight.first?.weightLbs
        var weightTrend: Double? = nil
        if snapsWithWeight.count >= 4 {
            let half = snapsWithWeight.count / 2
            let recentAvg = snapsWithWeight.prefix(half).reduce(0.0) { $0 + ($1.weightLbs ?? 0) } / Double(half)
            let olderAvg = snapsWithWeight.suffix(half).reduce(0.0) { $0 + ($1.weightLbs ?? 0) } / Double(half)
            // Positive = gaining (recent > older), scale to per-week assuming ~14 days
            weightTrend = (recentAvg - olderAvg) / (Double(snapsWithWeight.count) / 7.0)
        }

        // Today's workout (from today's snapshot if already loaded)
        var todayWorkoutType: String? = nil
        var todayWorkoutMins: Int? = nil
        var todaySnapDescriptor = FetchDescriptor<HealthSnapshot>(
            predicate: #Predicate { $0.dateString == todayString }
        )
        todaySnapDescriptor.fetchLimit = 1
        if let todaySnap = try? modelContext.fetch(todaySnapDescriptor).first {
            todayWorkoutType = todaySnap.workoutType
            todayWorkoutMins = todaySnap.workoutMinutes
        }

        return BriefContext(
            yesterdaySleepHours: yesterdaySnap?.sleepHours,
            yesterdayCalories: yesterdayLog?.totalCalories ?? 0,
            yesterdayCalorieTarget: settings.calorieTarget,
            yesterdayProtein: yesterdayLog?.totalProtein ?? 0,
            yesterdayProteinTarget: settings.proteinTarget,
            avgSleepHours: avgSleep,
            avgCalories: avgCalories,
            avgProtein: avgProtein,
            loggingConsistencyPct: loggingPct,
            latestWeightLbs: latestWeight,
            weightTrendLbsPerWeek: weightTrend,
            currentCalorieTarget: settings.calorieTarget,
            currentProteinTarget: settings.proteinTarget,
            todayWorkoutType: todayWorkoutType,
            todayWorkoutMinutes: todayWorkoutMins
        )
    }
}
