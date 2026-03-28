import SwiftUI
import SwiftData

struct DayDetailView: View {
    let dayLog: DayLog

    @Environment(\.modelContext) private var modelContext
    @State private var settings: UserSettings?
    @State private var existingSnapshot: HealthSnapshot?
    @State private var showLogMeal = false
    @State private var processingMealId: UUID?

    @AppStorage("healthKitEnabled") private var healthKitEnabled = false
    @AppStorage("adjustCaloriesForActivity") private var adjustCaloriesForActivity = false
    @StateObject private var healthManager = HealthDataManager()

    private var effectiveCalorieTarget: Int {
        let base = settings?.calorieTarget ?? 2200
        guard adjustCaloriesForActivity,
              let active = (existingSnapshot ?? healthManager.snapshot)?.activeCalories,
              active > 0 else { return base }
        return base + active
    }

    private var displaySnapshot: HealthSnapshot? { healthManager.snapshot ?? existingSnapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                summaryCard
                healthSection
                mealsList
            }
            .padding()
        }
        .navigationTitle(dayLog.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showLogMeal = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
            }
        }
        .sheet(isPresented: $showLogMeal, onDismiss: loadSnapshot) {
            LogMealView(defaultDate: dayLog.date)
        }
        .onAppear(perform: loadData)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(spacing: 16) {
            MacroProgressBar(
                label: "Calories",
                current: Double(dayLog.totalCalories),
                target: Double(effectiveCalorieTarget),
                unit: "",
                color: FuelTheme.calorieColor
            )
            MacroProgressBar(
                label: "Protein",
                current: dayLog.totalProtein,
                target: Double(settings?.proteinTarget ?? 160),
                unit: "g",
                color: FuelTheme.proteinColor
            )
            HStack(spacing: 16) {
                miniMacro(label: "Carbs", value: dayLog.totalCarbs,
                          target: Double(settings?.carbsTarget ?? 250), color: FuelTheme.carbsColor)
                miniMacro(label: "Fat",   value: dayLog.totalFat,
                          target: Double(settings?.fatTarget ?? 70),    color: FuelTheme.fatColor)
            }
        }
        .padding()
        .background(FuelTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func miniMacro(label: String, value: Double, target: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(FuelTheme.textSecondary)
            Text("\(Int(value))g").font(.headline).foregroundStyle(color)
            Text("/ \(Int(target))g").font(.caption2).foregroundStyle(FuelTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Health Section

    @ViewBuilder
    private var healthSection: some View {
        if healthKitEnabled {
            if let snap = displaySnapshot {
                HealthStatsCard(snapshot: snap)
            } else if healthManager.isLoading {
                ProgressView("Fetching health data…")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(FuelTheme.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                fetchHealthButton
            }
        }
    }

    private var fetchHealthButton: some View {
        Button {
            Task { await healthManager.load(for: dayLog.date, modelContext: modelContext) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.clockwise.heart.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Fetch Health Data")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(FuelTheme.textPrimary)
                    Text("Pull sleep, steps & workouts for this day")
                        .font(.caption).foregroundStyle(FuelTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(FuelTheme.textSecondary)
            }
            .padding()
            .background(FuelTheme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Meals List

    private var mealsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Meals").font(.headline)
                Spacer()
                let unprocessed = dayLog.meals.filter { !$0.isProcessed }.count
                if unprocessed > 0 {
                    Button {
                        Task { await processAll() }
                    } label: {
                        Label("Process All (\(unprocessed))", systemImage: "sparkles")
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.purple.opacity(0.12))
                            .foregroundStyle(.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(processingMealId != nil)
                }
            }

            if dayLog.meals.isEmpty {
                Text("No meals logged for this day.")
                    .font(.subheadline).foregroundStyle(FuelTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                let sorted = dayLog.meals.sorted { $0.timestamp < $1.timestamp }
                ForEach(sorted, id: \.id) { meal in
                    MealRow(
                        meal: meal,
                        isProcessing: processingMealId == meal.id,
                        onProcess: { Task { await processMeal(meal) } },
                        onDelete: { deleteMeal(meal) }
                    )
                    if meal.id != sorted.last?.id { Divider() }
                }
            }
        }
        .padding()
        .background(FuelTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Actions

    private func processMeal(_ meal: Meal) async {
        guard let settings else { return }
        processingMealId = meal.id
        let engine = NutritionEngine(modelContext: modelContext)
        try? await engine.processMeal(meal, apiKey: settings.apiKey)
        processingMealId = nil
    }

    private func deleteMeal(_ meal: Meal) {
        let engine = NutritionEngine(modelContext: modelContext)
        try? engine.deleteMeal(meal)
    }

    private func processAll() async {
        for meal in dayLog.meals.filter({ !$0.isProcessed }) {
            await processMeal(meal)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        let engine = NutritionEngine(modelContext: modelContext)
        settings = try? engine.settings()
        loadSnapshot()
    }

    private func loadSnapshot() {
        let dateStr = HealthSnapshot.dateFormatter.string(from: dayLog.date)
        let descriptor = FetchDescriptor<HealthSnapshot>(
            predicate: #Predicate { $0.dateString == dateStr }
        )
        existingSnapshot = try? modelContext.fetch(descriptor).first
    }
}
