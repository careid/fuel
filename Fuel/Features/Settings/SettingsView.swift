import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var settings: UserSettings?
    @State private var calorieTarget = 2200
    @State private var proteinTarget = 160
    @State private var carbsTarget = 250
    @State private var fatTarget = 70
    @State private var apiKey = ""
    @FocusState private var apiKeyFocused: Bool
    @AppStorage("healthKitEnabled") private var healthKitEnabled = false
    @AppStorage("adjustCaloriesForActivity") private var adjustCaloriesForActivity = false
    @AppStorage("morningBriefEnabled") private var morningBriefEnabled = true
    @AppStorage("briefHour") private var briefHour = 7
    @AppStorage("briefMinute") private var briefMinute = 30

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily Targets") {
                    targetRow(label: "Calories", value: $calorieTarget, unit: "cal", range: 1200...4000, step: 50)
                    targetRow(label: "Protein", value: $proteinTarget, unit: "g", range: 50...300, step: 5)
                    targetRow(label: "Carbs", value: $carbsTarget, unit: "g", range: 50...500, step: 10)
                    targetRow(label: "Fat", value: $fatTarget, unit: "g", range: 20...200, step: 5)
                    if healthKitEnabled {
                        Toggle("Adjust goal for exercise", isOn: $adjustCaloriesForActivity)
                        if adjustCaloriesForActivity {
                            Text("Daily calorie goal = base target + active calories burned. Use this if your target is a sedentary baseline, not a TDEE estimate.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Claude API") {
                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .focused($apiKeyFocused)

                    if apiKey.isEmpty {
                        Label("Required for meal analysis", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Label("API key configured", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Section("Morning Brief") {
                    Toggle("Daily morning brief", isOn: $morningBriefEnabled)
                        .onChange(of: morningBriefEnabled) { _, enabled in
                            ReminderManager.shared.scheduleMorningBrief(
                                enabled: enabled, hour: briefHour, minute: briefMinute
                            )
                        }
                    if morningBriefEnabled {
                        HStack {
                            Text("Notification time")
                            Spacer()
                            DatePicker(
                                "",
                                selection: briefTimeBinding,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .onChange(of: briefHour) { _, _ in
                                ReminderManager.shared.scheduleMorningBrief(
                                    enabled: morningBriefEnabled, hour: briefHour, minute: briefMinute
                                )
                            }
                            .onChange(of: briefMinute) { _, _ in
                                ReminderManager.shared.scheduleMorningBrief(
                                    enabled: morningBriefEnabled, hour: briefHour, minute: briefMinute
                                )
                            }
                        }
                        Text("Claude generates your brief when you first open the app each morning. The notification is a reminder to check in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notifications") {
                    NavigationLink("Reminders") { RemindersView() }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    LabeledContent("Model", value: "Claude Sonnet 4.6")
                }
            }
            .navigationTitle("Settings")
            .onAppear(perform: loadSettings)
            .onChange(of: calorieTarget) { _, _ in saveSettings() }
            .onChange(of: proteinTarget) { _, _ in saveSettings() }
            .onChange(of: carbsTarget) { _, _ in saveSettings() }
            .onChange(of: fatTarget) { _, _ in saveSettings() }
            .onChange(of: apiKeyFocused) { _, focused in
                // Save the API key only when the field loses focus, not on every keystroke
                if !focused { saveSettings() }
            }
        }
    }

    private var briefTimeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
                comps.hour = briefHour
                comps.minute = briefMinute
                return Calendar.current.date(from: comps) ?? .now
            },
            set: { date in
                briefHour = Calendar.current.component(.hour, from: date)
                briefMinute = Calendar.current.component(.minute, from: date)
            }
        )
    }

    private func targetRow(
        label: String,
        value: Binding<Int>,
        unit: String,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value.wrappedValue) \(unit)")
                .foregroundStyle(FuelTheme.textSecondary)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
        }
    }

    private func loadSettings() {
        let engine = NutritionEngine(modelContext: modelContext)
        guard let s = try? engine.settings() else { return }
        settings = s
        calorieTarget = s.calorieTarget
        proteinTarget = s.proteinTarget
        carbsTarget = s.carbsTarget
        fatTarget = s.fatTarget
        apiKey = s.apiKey
    }

    private func saveSettings() {
        guard let settings else { return }
        settings.calorieTarget = calorieTarget
        settings.proteinTarget = proteinTarget
        settings.carbsTarget = carbsTarget
        settings.fatTarget = fatTarget
        settings.apiKey = apiKey
        try? modelContext.save()
    }
}
