import Foundation
import HealthKit
import SwiftData

@MainActor
final class HealthDataManager: ObservableObject {
    private let store = HKHealthStore()

    @Published var snapshot: HealthSnapshot?
    @Published var isLoading = false

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType()
        ]
        for id: HKQuantityTypeIdentifier in [.stepCount, .activeEnergyBurned, .bodyMass, .restingHeartRate] {
            types.insert(HKQuantityType(id))
        }
        return types
    }

    func requestPermissions() async -> Bool {
        guard Self.isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            return true
        } catch {
            return false
        }
    }

    // Convenience: load today
    func load(modelContext: ModelContext) async {
        await load(for: .now, modelContext: modelContext)
    }

    // Load (or refresh) the HealthSnapshot for any given date
    func load(for date: Date, modelContext: ModelContext) async {
        guard Self.isAvailable else { return }
        isLoading = true
        defer { isLoading = false }

        async let steps          = fetchSteps(for: date)
        async let activeCalories = fetchActiveCalories(for: date)
        async let weightSample   = fetchLatestWeight(asOf: date)
        async let rhr            = fetchRestingHeartRate(asOf: date)
        async let sleep          = fetchSleep(nightOf: date)
        async let workout        = fetchWorkout(on: date)

        let (s, acRaw, ws, r, sl, wo) = await (steps, activeCalories, weightSample, rhr, sleep, workout)

        guard s != nil || acRaw != nil || ws != nil || r != nil || sl != nil || wo != nil else { return }

        // Step-based active-calorie fallback. When the user isn't wearing the
        // watch, HealthKit returns no/very low active energy even though steps
        // came in from the phone. Estimate ~0.04 cal/step scaled by body weight,
        // and use it when measured cal is missing or implausibly low for the steps.
        let weightKgForEstimate = ws?.kg ?? 75.0
        let expected = (s.map(Double.init) ?? 0) * 0.04 * weightKgForEstimate / 70.0
        let usedFallback: Bool
        let activeCal: Int?
        if let s, s > 1000, expected > 0,
           Double(acRaw ?? 0) < expected * 0.4 {
            activeCal = Int(expected)
            usedFallback = true
        } else {
            activeCal = acRaw
            usedFallback = false
        }

        let dateStr = HealthSnapshot.dateFormatter.string(from: date)
        let descriptor = FetchDescriptor<HealthSnapshot>(
            predicate: #Predicate { $0.dateString == dateStr }
        )
        let snap: HealthSnapshot
        if let existing = try? modelContext.fetch(descriptor).first {
            snap = existing
        } else {
            snap = HealthSnapshot(date: date)
            modelContext.insert(snap)
        }

        snap.steps                   = s
        snap.activeCalories          = activeCal
        snap.activeCaloriesEstimated = usedFallback
        snap.weightKg                = ws?.kg
        snap.weightMeasuredAt        = ws?.measuredAt
        snap.restingHeartRate        = r
        snap.sleepSeconds            = sl.map { Int($0) }

        if let wo {
            snap.workoutType    = wo.workoutActivityType.name
            snap.workoutMinutes = Int(wo.duration / 60)
            let energyStats = wo.statistics(for: HKQuantityType(.activeEnergyBurned))
            snap.workoutCalories = energyStats?.sumQuantity().map { Int($0.doubleValue(for: .kilocalorie())) }

            // Post-workout reminder only fires for today's workouts
            if Calendar.current.isDateInToday(date) {
                let notifKey = "fuel.lastWorkoutNotif"
                let lastNotif = UserDefaults.standard.double(forKey: notifKey)
                if wo.endDate.timeIntervalSince1970 > lastNotif {
                    UserDefaults.standard.set(wo.endDate.timeIntervalSince1970, forKey: notifKey)
                    ReminderManager.shared.sendPostWorkoutReminder(
                        type: wo.workoutActivityType.name,
                        calories: snap.workoutCalories
                    )
                }
            }
        } else {
            snap.workoutType    = nil
            snap.workoutMinutes = nil
            snap.workoutCalories = nil
        }

        try? modelContext.save()
        snapshot = snap
    }

    // MARK: - Fetchers

    private func fetchSteps(for date: Date) async -> Int? {
        await withCheckedContinuation { cont in
            let cal = Calendar.current
            let start = cal.startOfDay(for: date)
            let end = cal.isDateInToday(date) ? Date.now : (cal.date(byAdding: .day, value: 1, to: start) ?? Date.now)
            let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let q = HKStatisticsQuery(quantityType: HKQuantityType(.stepCount),
                                      quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity().map { Int($0.doubleValue(for: .count())) })
            }
            store.execute(q)
        }
    }

    private func fetchActiveCalories(for date: Date) async -> Int? {
        await withCheckedContinuation { cont in
            let cal = Calendar.current
            let start = cal.startOfDay(for: date)
            let end = cal.isDateInToday(date) ? Date.now : (cal.date(byAdding: .day, value: 1, to: start) ?? Date.now)
            let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let q = HKStatisticsQuery(quantityType: HKQuantityType(.activeEnergyBurned),
                                      quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity().map { Int($0.doubleValue(for: .kilocalorie())) })
            }
            store.execute(q)
        }
    }

    struct WeightSample { let kg: Double; let measuredAt: Date }

    private func fetchLatestWeight(asOf date: Date) async -> WeightSample? {
        await withCheckedContinuation { cont in
            let cal = Calendar.current
            // Use the end of the target day so historical fetches don't show future readings
            let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) ?? Date.now
            let pred = HKQuery.predicateForSamples(withStart: nil, end: endOfDay, options: .strictEndDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: HKQuantityType(.bodyMass),
                                  predicate: pred, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    cont.resume(returning: nil)
                    return
                }
                let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                cont.resume(returning: WeightSample(kg: kg, measuredAt: sample.endDate))
            }
            store.execute(q)
        }
    }

    private func fetchRestingHeartRate(asOf date: Date) async -> Double? {
        await withCheckedContinuation { cont in
            let cal = Calendar.current
            let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) ?? Date.now
            let pred = HKQuery.predicateForSamples(withStart: nil, end: endOfDay, options: .strictEndDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: HKQuantityType(.restingHeartRate),
                                  predicate: pred, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let bpm = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                cont.resume(returning: bpm)
            }
            store.execute(q)
        }
    }

    private func fetchSleep(nightOf date: Date) async -> TimeInterval? {
        await withCheckedContinuation { cont in
            let cal = Calendar.current
            let dayStart = cal.startOfDay(for: date)
            // Window: 6pm prior day → noon of `date`. The previous version ended
            // at midnight, which truncated every morning's sleep.
            guard let windowStart = cal.date(byAdding: .hour, value: -6, to: dayStart),
                  let windowEnd = cal.date(byAdding: .hour, value: 12, to: dayStart) else {
                cont.resume(returning: nil)
                return
            }
            let pred = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd)
            let q = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis),
                                  predicate: pred, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: Self.totalAsleep(samples))
            }
            store.execute(q)
        }
    }

    // Positively filter "asleep" stages, then merge overlapping intervals so
    // duplicate samples (Watch + iPhone, or multiple sleep apps) aren't double-counted.
    static func totalAsleep(_ samples: [HKCategorySample]) -> TimeInterval? {
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleep.rawValue
        ]
        let intervals = samples
            .filter { asleepValues.contains($0.value) }
            .map { ($0.startDate, $0.endDate) }
            .sorted { $0.0 < $1.0 }

        guard !intervals.isEmpty else { return nil }

        var merged: [(Date, Date)] = []
        for (start, end) in intervals {
            if var last = merged.last, start <= last.1 {
                last.1 = max(last.1, end)
                merged[merged.count - 1] = last
            } else {
                merged.append((start, end))
            }
        }
        let total = merged.reduce(0.0) { $0 + $1.1.timeIntervalSince($1.0) }
        return total > 0 ? total : nil
    }

    private func fetchWorkout(on date: Date) async -> HKWorkout? {
        await withCheckedContinuation { cont in
            let cal = Calendar.current
            let start = cal.startOfDay(for: date)
            let end = cal.isDateInToday(date) ? Date.now : (cal.date(byAdding: .day, value: 1, to: start) ?? Date.now)
            let pred = HKQuery.predicateForSamples(withStart: start, end: end)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                  predicate: pred, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: samples?.first as? HKWorkout)
            }
            store.execute(q)
        }
    }
}

// MARK: - HKWorkoutActivityType name

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running:                                           return "Run"
        case .cycling:                                          return "Ride"
        case .swimming:                                         return "Swim"
        case .walking:                                          return "Walk"
        case .functionalStrengthTraining,
             .traditionalStrengthTraining:                      return "Strength"
        case .yoga:                                             return "Yoga"
        case .highIntensityIntervalTraining:                    return "HIIT"
        default:                                                return "Workout"
        }
    }
}
