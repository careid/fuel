import SwiftUI
import SwiftData
import CoreLocation

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("healthKitEnabled") private var healthKitEnabled = false

    @State private var page = 0
    @State private var calorieTarget = 2200
    @State private var proteinTarget = 160
    @State private var remindersEnabled = true
    @State private var kitchenStatus: KitchenStatus = .notSet
    @State private var isRequestingHealth = false

    @StateObject private var healthManager = HealthDataManager()
    @StateObject private var locationHelper = LocationHelper()

    private enum KitchenStatus { case notSet, loading, set, failed }

    var body: some View {
        ZStack {
            FuelTheme.backgroundPrimary.ignoresSafeArea()
            currentPage
                .id(page)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
        }
        .animation(.easeInOut(duration: 0.3), value: page)
    }

    @ViewBuilder
    private var currentPage: some View {
        switch page {
        case 0: welcomePage
        case 1: goalsPage
        case 2: healthPage
        case 3: remindersPage
        default: allSetPage
        }
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        pageShell {
            Spacer()
            VStack(spacing: 24) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(FuelTheme.calorieColor)
                VStack(spacing: 8) {
                    Text("Fuel")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Track your nutrition.\nPowered by AI.")
                        .font(.title3)
                        .foregroundStyle(FuelTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            primaryButton("Get Started") { page = 1 }
        }
    }

    // MARK: - Goals

    private var goalsPage: some View {
        pageShell {
            header(icon: "target", iconColor: .orange,
                   title: "Set Your Targets",
                   subtitle: "Daily goals for calories and protein. Adjust anytime in Settings.")

            VStack(spacing: 0) {
                stepperRow(label: "Calories", value: $calorieTarget, step: 50, range: 1200...4000, unit: "cal")
                Divider().padding(.horizontal)
                stepperRow(label: "Protein",  value: $proteinTarget, step: 5,  range: 50...300,   unit: "g")
            }
            .background(FuelTheme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer()
            primaryButton("Continue") {
                saveGoals()
                page = 2
            }
        }
    }

    // MARK: - Health

    private var healthPage: some View {
        pageShell {
            header(icon: "heart.text.square.fill", iconColor: .red,
                   title: "Connect Apple Health",
                   subtitle: "Fuel reads — never writes — your health data to give context to your meals.")

            VStack(alignment: .leading, spacing: 14) {
                bulletRow(icon: "moon.fill",       color: .indigo,  text: "Sleep quality and duration")
                bulletRow(icon: "figure.walk",     color: .green,   text: "Daily step count")
                bulletRow(icon: "flame.fill",      color: .orange,  text: "Active calories burned")
                bulletRow(icon: "scalemass.fill",  color: .blue,    text: "Body weight (Renpho, etc.)")
                bulletRow(icon: "figure.run",      color: .purple,  text: "Workout detection")
            }
            .padding()
            .background(FuelTheme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer()

            primaryButton(isRequestingHealth ? "Connecting…" : "Connect Health") {
                guard !isRequestingHealth else { return }
                isRequestingHealth = true
                Task {
                    let granted = await healthManager.requestPermissions()
                    if granted { healthKitEnabled = true }
                    isRequestingHealth = false
                    page = 3
                }
            }
            .disabled(isRequestingHealth)

            skipButton { page = 3 }
        }
    }

    // MARK: - Reminders

    private var remindersPage: some View {
        pageShell {
            header(icon: "bell.badge.fill", iconColor: .purple,
                   title: "Smart Reminders",
                   subtitle: "Gentle nudges to log meals — kitchen arrival, post-workout, evening summary.")

            VStack(spacing: 0) {
                Toggle(isOn: $remindersEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Reminders")
                            .font(.subheadline).fontWeight(.medium)
                        Text("Kitchen, time-based, and post-workout")
                            .font(.caption).foregroundStyle(FuelTheme.textSecondary)
                    }
                }
                .padding()
                .tint(.purple)

                if remindersEnabled {
                    Divider().padding(.horizontal)

                    Button {
                        kitchenStatus = .loading
                        locationHelper.onLocation = { coord in
                            saveKitchenLocation(coord)
                            kitchenStatus = .set
                        }
                        locationHelper.onFailure = { kitchenStatus = .failed }
                        locationHelper.requestLocation()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: kitchenIcon)
                                .foregroundStyle(kitchenColor)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Set Kitchen Location")
                                    .font(.subheadline).fontWeight(.medium)
                                    .foregroundStyle(FuelTheme.textPrimary)
                                Text(kitchenSubtitle)
                                    .font(.caption).foregroundStyle(FuelTheme.textSecondary)
                            }
                            Spacer()
                            if kitchenStatus == .loading {
                                ProgressView().scaleEffect(0.8)
                            } else if kitchenStatus != .set {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(FuelTheme.textSecondary)
                            }
                        }
                        .padding()
                    }
                    .buttonStyle(.plain)
                    .disabled(kitchenStatus == .loading || kitchenStatus == .set)
                    .animation(.easeInOut, value: remindersEnabled)
                }
            }
            .background(FuelTheme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .animation(.easeInOut, value: remindersEnabled)

            Spacer()
            primaryButton("Continue") {
                saveReminders()
                page = 4
            }
        }
    }

    private var kitchenIcon: String {
        switch kitchenStatus {
        case .set:    return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default:      return "location.fill"
        }
    }

    private var kitchenColor: Color {
        switch kitchenStatus {
        case .set:    return .green
        case .failed: return .orange
        default:      return .blue
        }
    }

    private var kitchenSubtitle: String {
        switch kitchenStatus {
        case .notSet:  return "Use current location — reminds you when you arrive home"
        case .loading: return "Getting location…"
        case .set:     return "Kitchen location saved"
        case .failed:  return "Couldn't get location — set it later in Settings"
        }
    }

    // MARK: - All Set

    private var allSetPage: some View {
        pageShell {
            Spacer()
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                VStack(spacing: 8) {
                    Text("You're all set!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Start logging meals and Fuel\nwill handle the rest.")
                        .font(.title3)
                        .foregroundStyle(FuelTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            primaryButton("Start Logging") {
                hasCompletedOnboarding = true
            }
        }
    }

    // MARK: - Shared UI

    private func pageShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 24) { content() }
            .padding(.horizontal, 24)
            .padding(.top, 52)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func header(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(iconColor)
            VStack(spacing: 6) {
                Text(title)
                    .font(.title2).fontWeight(.bold)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(FuelTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(FuelTheme.calorieColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func skipButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Skip for now")
                .font(.subheadline)
                .foregroundStyle(FuelTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func stepperRow(label: String, value: Binding<Int>, step: Int, range: ClosedRange<Int>, unit: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline).fontWeight(.medium)
            Spacer()
            HStack(spacing: 16) {
                Button {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(FuelTheme.textSecondary)
                }
                Text("\(value.wrappedValue) \(unit)")
                    .font(.subheadline).fontWeight(.semibold)
                    .frame(minWidth: 90, alignment: .center)
                    .monospacedDigit()
                Button {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(FuelTheme.calorieColor)
                }
            }
        }
        .padding()
    }

    private func bulletRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    // MARK: - Data

    private func saveGoals() {
        let engine = NutritionEngine(modelContext: modelContext)
        guard let s = try? engine.settings() else { return }
        s.calorieTarget = calorieTarget
        s.proteinTarget = proteinTarget
    }

    private func saveReminders() {
        let engine = NutritionEngine(modelContext: modelContext)
        guard let s = try? engine.settings() else { return }
        s.remindersEnabled = remindersEnabled
        s.geofenceEnabled  = remindersEnabled
    }

    private func saveKitchenLocation(_ coord: CLLocationCoordinate2D) {
        let engine = NutritionEngine(modelContext: modelContext)
        guard let s = try? engine.settings() else { return }
        s.kitchenLatitude  = coord.latitude
        s.kitchenLongitude = coord.longitude
    }
}

// MARK: - Location Helper

private final class LocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocation: ((CLLocationCoordinate2D) -> Void)?
    var onFailure: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            DispatchQueue.main.async { self.onFailure?() }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            DispatchQueue.main.async { self.onFailure?() }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        DispatchQueue.main.async { self.onLocation?(coord) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { self.onFailure?() }
    }
}
