import SwiftUI
import SwiftData
import CoreLocation

struct RemindersView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var settings: UserSettings?
    @State private var remindersEnabled = true
    @State private var geofenceEnabled = true
    @State private var hasLocation = false
    @State private var locatingError: String?

    @StateObject private var locator = LocationFetcher()

    var body: some View {
        Form {
            Section {
                Toggle("Enable Reminders", isOn: $remindersEnabled)
                    .onChange(of: remindersEnabled) { _, v in save(\.remindersEnabled, v) }
            } footer: {
                Text("Fuel will send nudges when you haven't logged meals and notify you after workouts.")
            }

            if remindersEnabled {
                Section {
                    timingRow(icon: "sunrise", label: "Breakfast check",  time: "9:30 AM")
                    timingRow(icon: "sun.max", label: "Lunch check",       time: "1:00 PM")
                    timingRow(icon: "sunset",  label: "Dinner check",      time: "7:00 PM")
                    timingRow(icon: "moon",    label: "Protein gap check", time: "8:00 PM")
                } header: {
                    Text("Meal Windows")
                } footer: {
                    Text("Skipped automatically when the meal is already logged. After 5 consecutive days of logging, breakfast and lunch checks are suppressed.")
                }

                Section {
                    Toggle("Notify when I arrive home", isOn: $geofenceEnabled)
                        .onChange(of: geofenceEnabled) { _, v in
                            save(\.geofenceEnabled, v)
                            if !v { ReminderManager.shared.stopGeofence() }
                            else if let coord = settings?.kitchenCoordinate {
                                ReminderManager.shared.startGeofence(
                                    latitude: coord.latitude,
                                    longitude: coord.longitude
                                )
                            }
                        }

                    if geofenceEnabled {
                        if hasLocation {
                            HStack(spacing: 8) {
                                Image(systemName: "location.fill").foregroundStyle(.green)
                                Text("Kitchen location set")
                                Spacer()
                                Button("Update") { Task { await setLocation() } }
                                    .font(.subheadline)
                                    .disabled(locator.isFetching)
                            }
                        } else {
                            Button {
                                Task { await setLocation() }
                            } label: {
                                if locator.isFetching {
                                    HStack { ProgressView(); Text("Getting location…") }
                                } else {
                                    Label("Set Kitchen Location", systemImage: "location")
                                }
                            }
                            .disabled(locator.isFetching)
                        }

                        if let err = locatingError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Kitchen Geofence")
                } footer: {
                    Text("Fuel will ping you when you arrive home during meal hours (7 AM – 9 PM), with a 2-hour cooldown between alerts. Requires Always On location permission.")
                }

                Section {
                    Label("Triggers automatically via Apple Health", systemImage: "figure.run")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Post-Workout")
                } footer: {
                    Text("When a new workout is detected, Fuel sends a one-time nudge to log your recovery meal.")
                }
            }
        }
        .navigationTitle("Reminders")
        .onAppear(perform: loadSettings)
    }

    // MARK: - Helpers

    private func timingRow(icon: String, label: String, time: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.orange).frame(width: 22)
            Text(label)
            Spacer()
            Text(time).foregroundStyle(.secondary).font(.subheadline)
        }
    }

    private func loadSettings() {
        let engine = NutritionEngine(modelContext: modelContext)
        guard let s = try? engine.settings() else { return }
        settings = s
        remindersEnabled = s.remindersEnabled
        geofenceEnabled = s.geofenceEnabled
        hasLocation = s.hasKitchenLocation
    }

    private func save<T>(_ keyPath: ReferenceWritableKeyPath<UserSettings, T>, _ value: T) {
        guard let settings else { return }
        settings[keyPath: keyPath] = value
        try? modelContext.save()
    }

    private func setLocation() async {
        locatingError = nil
        guard let loc = await locator.fetch() else {
            locatingError = locator.error ?? "Couldn't get location."
            return
        }
        guard let settings else { return }
        settings.kitchenLatitude  = loc.coordinate.latitude
        settings.kitchenLongitude = loc.coordinate.longitude
        try? modelContext.save()
        hasLocation = true

        if geofenceEnabled {
            ReminderManager.shared.startGeofence(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude
            )
        }
    }
}

// MARK: - LocationFetcher

@MainActor
final class LocationFetcher: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isFetching = false
    @Published var error: String?

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func fetch() async -> CLLocation? {
        isFetching = true
        error = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            try? await Task.sleep(for: .seconds(1))
        case .denied, .restricted:
            error = "Location access denied. Enable in Settings → Privacy → Location Services."
            isFetching = false
            return nil
        default:
            break
        }

        return await withCheckedContinuation { cont in
            continuation = cont
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            isFetching = false
            continuation?.resume(returning: locations.first)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            isFetching = false
            self.error = error.localizedDescription
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }
}
