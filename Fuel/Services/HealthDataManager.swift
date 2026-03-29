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
        async let weight         = fetchLatestWeight(asOf: date)
        async let rhr            = fetchRestingHeartRate(asOf: date)
        async let sleep          = fetchSleep(nightOf: date)
        async let workout        = fetchWorkout(on: date)

        let (s, ac, w, r, sl, wo) = await (steps, activeCalories, weight, rhr, sleep, workout)

        guard s != nil || ac != nil || w != nil || r != nil || sl != nil || wo != nil else { return }

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

        snap.steps            = s
        snap.activeCalories   = ac
        snap.weightKg         = w
        snap.restingHeartRate = r
        snap.sleepSeconds     = sl.map { Int($0) }

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

    private func fetchLatestWeight(asOf date: Date) async -> Double? {
        await withCheckedContinuation { cont in
            let cal = Calendar.current
            // Use the end of the target day so historical fetches don't show future readings
            let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) ?? Date.now
            let pred = HKQuery.predicateForSamples(withStart: nil, end: endOfDay, options: .strictEndDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: HKQuantityType(.bodyMass),
                                  predicate: pred, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let kg = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .gramUnit(with: .kilo))
                cont.resume(returning: kg)
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
            guard let sixPmPrior = cal.date(byAdding: .hour, value: -6,
                                            to: cal.startOfDay(for: date)) else {
                cont.resume(returning: nil)
                return
            }
            let dayStart = cal.startOfDay(for: date)
            let pred = HKQuery.predicateForSamples(withStart: sixPmPrior, end: dayStart)
            let q = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis),
                                  predicate: pred, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    cont.resume(returning: nil)
                    return
                }
                let total = samples
                    .filter { $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: total > 0 ? total : nil)
            }
            store.execute(q)
        }
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
