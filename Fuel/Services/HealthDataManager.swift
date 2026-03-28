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

    func load(modelContext: ModelContext) async {
        guard Self.isAvailable else { return }
        isLoading = true
        defer { isLoading = false }

        async let steps          = fetchTodaySteps()
        async let activeCalories = fetchTodayActiveCalories()
        async let weight         = fetchLatestWeight()
        async let rhr            = fetchRestingHeartRate()
        async let sleep          = fetchLastNightSleep()
        async let workout        = fetchLatestWorkout()

        let (s, ac, w, r, sl, wo) = await (steps, activeCalories, weight, rhr, sleep, workout)

        // If nothing came back the user likely hasn't granted permission
        guard s != nil || ac != nil || w != nil || r != nil || sl != nil || wo != nil else { return }

        // Upsert today's snapshot
        let todayStr = HealthSnapshot.dateFormatter.string(from: .now)
        let descriptor = FetchDescriptor<HealthSnapshot>(
            predicate: #Predicate { $0.dateString == todayStr }
        )
        let snap: HealthSnapshot
        if let existing = try? modelContext.fetch(descriptor).first {
            snap = existing
        } else {
            snap = HealthSnapshot()
            modelContext.insert(snap)
        }

        snap.steps          = s
        snap.activeCalories = ac
        snap.weightKg       = w
        snap.restingHeartRate = r
        snap.sleepSeconds   = sl.map { Int($0) }

        if let wo {
            snap.workoutType    = wo.workoutActivityType.name
            snap.workoutMinutes = Int(wo.duration / 60)
            let energyStats = wo.statistics(for: HKQuantityType(.activeEnergyBurned))
            snap.workoutCalories = energyStats?.sumQuantity().map { Int($0.doubleValue(for: .kilocalorie())) }

            // Post-workout reminder — fire once per workout session
            let notifKey = "fuel.lastWorkoutNotif"
            let lastNotif = UserDefaults.standard.double(forKey: notifKey)
            if wo.endDate.timeIntervalSince1970 > lastNotif {
                UserDefaults.standard.set(wo.endDate.timeIntervalSince1970, forKey: notifKey)
                ReminderManager.shared.sendPostWorkoutReminder(
                    type: wo.workoutActivityType.name,
                    calories: snap.workoutCalories
                )
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

    private func fetchTodaySteps() async -> Int? {
        await withCheckedContinuation { cont in
            let type = HKQuantityType(.stepCount)
            let start = Calendar.current.startOfDay(for: .now)
            let pred = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity().map { Int($0.doubleValue(for: .count())) })
            }
            store.execute(q)
        }
    }

    private func fetchTodayActiveCalories() async -> Int? {
        await withCheckedContinuation { cont in
            let type = HKQuantityType(.activeEnergyBurned)
            let start = Calendar.current.startOfDay(for: .now)
            let pred = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity().map { Int($0.doubleValue(for: .kilocalorie())) })
            }
            store.execute(q)
        }
    }

    private func fetchLatestWeight() async -> Double? {
        await withCheckedContinuation { cont in
            let type = HKQuantityType(.bodyMass)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let kg = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .gramUnit(with: .kilo))
                cont.resume(returning: kg)
            }
            store.execute(q)
        }
    }

    private func fetchRestingHeartRate() async -> Double? {
        await withCheckedContinuation { cont in
            let type = HKQuantityType(.restingHeartRate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let bpm = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                cont.resume(returning: bpm)
            }
            store.execute(q)
        }
    }

    private func fetchLastNightSleep() async -> TimeInterval? {
        await withCheckedContinuation { cont in
            guard let sixPmYesterday = Calendar.current.date(
                byAdding: .hour, value: -18,
                to: Calendar.current.startOfDay(for: .now)
            ) else {
                cont.resume(returning: nil)
                return
            }
            let type = HKCategoryType(.sleepAnalysis)
            let pred = HKQuery.predicateForSamples(withStart: sixPmYesterday, end: .now)
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
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

    private func fetchLatestWorkout() async -> HKWorkout? {
        await withCheckedContinuation { cont in
            let start = Calendar.current.startOfDay(for: .now)
            let pred = HKQuery.predicateForSamples(withStart: start, end: .now)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: pred,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
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
