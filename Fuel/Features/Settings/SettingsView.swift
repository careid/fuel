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

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily Targets") {
                    targetRow(label: "Calories", value: $calorieTarget, unit: "cal", range: 1200...4000, step: 50)
                    targetRow(label: "Protein", value: $proteinTarget, unit: "g", range: 50...300, step: 5)
                    targetRow(label: "Carbs", value: $carbsTarget, unit: "g", range: 50...500, step: 10)
                    targetRow(label: "Fat", value: $fatTarget, unit: "g", range: 20...200, step: 5)
                }

                Section("Claude API") {
                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()

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

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Model", value: "Claude Sonnet 4.6")
                }
            }
            .navigationTitle("Settings")
            .onAppear(perform: loadSettings)
            .onChange(of: calorieTarget) { _, _ in saveSettings() }
            .onChange(of: proteinTarget) { _, _ in saveSettings() }
            .onChange(of: carbsTarget) { _, _ in saveSettings() }
            .onChange(of: fatTarget) { _, _ in saveSettings() }
            .onChange(of: apiKey) { _, _ in saveSettings() }
        }
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
