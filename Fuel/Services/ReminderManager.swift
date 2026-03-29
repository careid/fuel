import Foundation
import UserNotifications
import CoreLocation

// Notification identifiers
private enum NotifID {
    static let breakfast   = "fuel.breakfast"
    static let lunch       = "fuel.lunch"
    static let dinner      = "fuel.dinner"
    static let protein     = "fuel.protein"
    static let postWorkout = "fuel.postworkout"
    static let geofence    = "fuel.geofence"
    static let morningBrief = "fuel.morningBrief"
}

@MainActor
final class ReminderManager: NSObject, ObservableObject {
    static let shared = ReminderManager()
    private override init() {
        super.init()
        center.delegate = self
    }

    private let center = UNUserNotificationCenter.current()
    private var locationManager: CLLocationManager?

    // MARK: - Permissions

    @discardableResult
    func requestPermissions() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: - Time-Based + Evening Protein
    // Call on app foreground and after saving a meal.

    func reschedule(log: DayLog?, settings: UserSettings) {
        guard settings.remindersEnabled else { cancelTimeReminders(); return }

        let meals = log?.meals ?? []
        let cal = Calendar.current
        let nowMinutes = cal.component(.hour, from: .now) * 60 + cal.component(.minute, from: .now)

        // Adaptive: suppress breakfast/lunch checks after 5 consistent days
        let quiet = loggingStreak >= 5

        if !quiet {
            // Breakfast at 9:30 — skip if logged or past 11am
            let hasBreakfast = meals.contains { $0.mealType == .breakfast }
            if !hasBreakfast && nowMinutes < 11 * 60 {
                schedule(id: NotifID.breakfast, title: "Breakfast logged?",
                         body: "Don't forget to log your morning meal.", hour: 9, minute: 30)
            } else {
                cancel(NotifID.breakfast)
            }

            // Lunch at 1pm — skip if logged or past 3pm
            let hasLunch = meals.contains { $0.mealType == .lunch }
            if !hasLunch && nowMinutes < 15 * 60 {
                schedule(id: NotifID.lunch, title: "Log lunch?",
                         body: "It's around lunchtime — tap to log your meal.", hour: 13, minute: 0)
            } else {
                cancel(NotifID.lunch)
            }
        }

        // Dinner at 7pm — skip if logged or past 8pm
        let hasDinner = meals.contains { $0.mealType == .dinner }
        if !hasDinner && nowMinutes < 20 * 60 {
            schedule(id: NotifID.dinner, title: "Log dinner?",
                     body: "Don't forget to log your evening meal.", hour: 19, minute: 0)
        } else {
            cancel(NotifID.dinner)
        }

        // Evening protein gap at 8pm
        if let log {
            let gap = Double(settings.proteinTarget) - log.totalProtein
            if gap > 20 {
                let body = "You're \(Int(gap))g short on protein. A shake or chicken would close the gap."
                schedule(id: NotifID.protein, title: "Protein check", body: body, hour: 20, minute: 0)
            } else {
                cancel(NotifID.protein)
            }
        }
    }

    // MARK: - Morning Brief (daily repeat)

    func scheduleMorningBrief(enabled: Bool, hour: Int = 7, minute: Int = 30) {
        cancel(NotifID.morningBrief)
        guard enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Good morning"
        content.body = "Your daily brief is ready — tap to see today's plan."
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: NotifID.morningBrief, content: content, trigger: trigger))
    }

    // MARK: - Post-Workout (immediate, one-shot)

    func sendPostWorkoutReminder(type: String, calories: Int?) {
        let calStr = calories.map { " You burned ~\($0) cal." } ?? ""
        let content = UNMutableNotificationContent()
        content.title = "Recovery meal?"
        content.body = "\(type) done!\(calStr) Log your post-workout meal."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: NotifID.postWorkout, content: content, trigger: nil))
    }

    // MARK: - Geofence

    private let geofenceRadius: Double = 30   // metres
    private let geofenceRegionID = "fuel.kitchen"
    private let geofenceCooldownKey = "fuel.lastGeofenceNotif"

    func startGeofence(latitude: Double, longitude: Double) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        stopGeofence()
        let mgr = CLLocationManager()
        mgr.delegate = self
        mgr.requestAlwaysAuthorization()
        locationManager = mgr

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: geofenceRadius,
            identifier: geofenceRegionID
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        mgr.startMonitoring(for: region)
    }

    func stopGeofence() {
        guard let mgr = locationManager else { return }
        mgr.monitoredRegions.forEach { mgr.stopMonitoring(for: $0) }
        locationManager = nil
    }

    // MARK: - Streak Tracking

    private let streakKey     = "fuel.loggingStreak"
    private let streakDateKey = "fuel.lastStreakDate"

    var loggingStreak: Int {
        get { UserDefaults.standard.integer(forKey: streakKey) }
        set { UserDefaults.standard.set(newValue, forKey: streakKey) }
    }

    func updateStreak(hadMealsToday: Bool) {
        let today = DayLog.dateFormatter.string(from: .now)
        let lastDate = UserDefaults.standard.string(forKey: streakDateKey) ?? ""
        guard today != lastDate else { return }
        UserDefaults.standard.set(today, forKey: streakDateKey)
        loggingStreak = hadMealsToday ? loggingStreak + 1 : 0
    }

    // MARK: - Helpers

    private func schedule(id: String, title: String, body: String, hour: Int, minute: Int) {
        // Don't schedule if this time has already passed today
        let cal = Calendar.current
        let nowMins = cal.component(.hour, from: .now) * 60 + cal.component(.minute, from: .now)
        guard (hour * 60 + minute) > nowMins else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func cancel(_ id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    private func cancelTimeReminders() {
        center.removePendingNotificationRequests(withIdentifiers: [
            NotifID.breakfast, NotifID.lunch, NotifID.dinner, NotifID.protein
        ])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension ReminderManager: UNUserNotificationCenterDelegate {
    // Show banners/sound even when the app is in the foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // Deep-link: tapping any Fuel notification opens the app (LogMeal could be added here later)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

// MARK: - CLLocationManagerDelegate

extension ReminderManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == "fuel.kitchen" else { return }

        let hour = Calendar.current.component(.hour, from: .now)
        guard (7...21).contains(hour) else { return }

        // 2-hour cooldown between geofence pings
        let key = "fuel.lastGeofenceNotif"
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           Date.now.timeIntervalSince(last) < 7200 { return }
        UserDefaults.standard.set(Date.now, forKey: key)

        let content = UNMutableNotificationContent()
        content.title = "Home? Log your meal."
        content.body = "You just arrived — tap to log what you had."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "fuel.geofence", content: content, trigger: nil)
        )
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     monitoringDidFailFor region: CLRegion?,
                                     withError error: Error) {}
}
