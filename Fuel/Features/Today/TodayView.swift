import SwiftUI
import SwiftData

struct TodayView: View {
    @Binding var showLogMeal: Bool
    @Environment(\.modelContext) private var modelContext

    @State private var todayLog: DayLog?
    @State private var settings: UserSettings?
    @State private var processingMealId: UUID?
    @State private var todayBrief: DailyBrief?
    @State private var isGeneratingBrief = false
    @State private var showLogWorkout = false
    @State private var claudeInsight: String?
    @State private var isLoadingInsight = false
    @State private var insightMealCount: Int = -1
    @State private var processingError: String?

    @AppStorage("healthKitEnabled") private var healthKitEnabled = false
    @AppStorage("adjustCaloriesForActivity") private var adjustCaloriesForActivity = false
    @AppStorage("morningBriefEnabled") private var morningBriefEnabled = true
    @StateObject private var healthManager = HealthDataManager()

    private var effectiveCalorieTarget: Int {
        let base = settings?.calorieTarget ?? 2200
        guard adjustCaloriesForActivity,
              let active = healthManager.snapshot?.activeCalories,
              active > 0 else { return base }
        return base + active
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    DailyBriefCard(
                        brief: todayBrief,
                        isLoading: isGeneratingBrief,
                        onApplyTargets: applyBriefTargets
                    )
                    dailySummaryCard
                    claudeInsightCard
                    healthSection
                    workoutsList
                    mealsList
                }
                .padding()
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showLogMeal = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .onAppear {
                loadData()
                if healthKitEnabled {
                    Task { await healthManager.load(modelContext: modelContext) }
                }
            }
            .onChange(of: showLogMeal) { _, isShowing in
                if !isShowing { loadData() }
            }
            .onChange(of: todayLog?.meals.count) { _, _ in
                loadInsightIfNeeded()
            }
            .sheet(isPresented: $showLogWorkout, onDismiss: loadData) {
                LogWorkoutView()
            }
        }
    }

    // MARK: - Daily Summary

    private var dailySummaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.headline)
                Spacer()
            }

            MacroProgressBar(
                label: "Calories",
                current: Double(todayLog?.totalCalories ?? 0),
                target: Double(effectiveCalorieTarget),
                unit: "",
                color: FuelTheme.calorieColor
            )

            if adjustCaloriesForActivity, let active = healthManager.snapshot?.activeCalories, active > 0 {
                HStack {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("\(settings?.calorieTarget ?? 2200) base + \(active) active = \(effectiveCalorieTarget) goal")
                        .font(.caption2)
                        .foregroundStyle(FuelTheme.textSecondary)
                    Spacer()
                }
            }

            MacroProgressBar(
                label: "Protein",
                current: todayLog?.totalProtein ?? 0,
                target: Double(settings?.proteinTarget ?? 160),
                unit: "g",
                color: FuelTheme.proteinColor
            )

            HStack(spacing: 16) {
                miniMacro(
                    label: "Carbs",
                    value: todayLog?.totalCarbs ?? 0,
                    target: Double(settings?.carbsTarget ?? 250),
                    color: FuelTheme.carbsColor
                )
                miniMacro(
                    label: "Fat",
                    value: todayLog?.totalFat ?? 0,
                    target: Double(settings?.fatTarget ?? 70),
                    color: FuelTheme.fatColor
                )
            }
        }
        .padding()
        .background(FuelTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func miniMacro(label: String, value: Double, target: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(FuelTheme.textSecondary)
            Text("\(Int(value))g")
                .font(.headline)
                .foregroundStyle(color)
            Text("/ \(Int(target))g")
                .font(.caption2)
                .foregroundStyle(FuelTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Claude Insight Card

    @ViewBuilder
    private var claudeInsightCard: some View {
        if isLoadingInsight {
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coach")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple)
                    Text("Thinking about your day...")
                        .font(.subheadline)
                        .foregroundStyle(FuelTheme.textSecondary)
                }
                Spacer()
                ProgressView().tint(.purple)
            }
            .padding()
            .background(insightCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if let insight = claudeInsight {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Coach")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple)
                    Text(insight)
                        .font(.subheadline)
                        .foregroundStyle(FuelTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .background(insightCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var insightCardBackground: some View {
        ZStack {
            FuelTheme.backgroundSecondary
            LinearGradient(
                colors: [Color.purple.opacity(0.07), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func loadInsightIfNeeded() {
        guard let log = todayLog, log.meals.count > 0 else { claudeInsight = nil; return }
        guard let settings, !settings.apiKey.isEmpty else { return }
        guard log.meals.count != insightMealCount else { return }
        insightMealCount = log.meals.count
        Task { await fetchInsight(log: log, settings: settings) }
    }

    private func fetchInsight(log: DayLog, settings: UserSettings) async {
        isLoadingInsight = true
        defer { isLoadingInsight = false }
        do {
            claudeInsight = try await ClaudeService().generateDailyInsight(
                proteinEaten: log.totalProtein,
                proteinTarget: settings.proteinTarget,
                caloriesEaten: log.totalCalories,
                calorieTarget: settings.calorieTarget,
                mealCount: log.meals.count,
                sleepHours: healthManager.snapshot?.sleepHours,
                apiKey: settings.apiKey
            )
        } catch {
            claudeInsight = nil
        }
    }

    // MARK: - Health Section

    @ViewBuilder
    private var healthSection: some View {
        if healthKitEnabled {
            if let snap = healthManager.snapshot {
                HealthStatsCard(snapshot: snap)
            }
        } else if HealthDataManager.isAvailable {
            connectHealthCard
        }
    }

    private var connectHealthCard: some View {
        Button {
            Task {
                if await healthManager.requestPermissions() {
                    healthKitEnabled = true
                    await healthManager.load(modelContext: modelContext)
                }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "heart.text.square.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect Apple Health")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(FuelTheme.textPrimary)
                    Text("See sleep, steps & workouts alongside your meals")
                        .font(.caption)
                        .foregroundStyle(FuelTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(FuelTheme.textSecondary)
            }
            .padding()
            .background(FuelTheme.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Workouts List

    private var workoutsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Workouts")
                    .font(.headline)
                Spacer()
                Button {
                    showLogWorkout = true
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(0.12))
                        .foregroundStyle(.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            let workouts = (todayLog?.workouts ?? []).sorted { $0.timestamp < $1.timestamp }
            if workouts.isEmpty {
                Text("No workouts logged yet")
                    .font(.subheadline)
                    .foregroundStyle(FuelTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(workouts, id: \.id) { workout in
                    workoutRow(workout)
                    if workout.id != workouts.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(FuelTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func workoutRow(_ workout: Workout) -> some View {
        HStack(spacing: 12) {
            Image(systemName: workout.workoutCategory.icon)
                .font(.title3)
                .foregroundStyle(.purple)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(workout.workoutCategory.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let notes = workout.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(FuelTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(workout.durationMinutes) min")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let cal = workout.caloriesBurned {
                    Text("\(cal) cal")
                        .font(.caption)
                        .foregroundStyle(FuelTheme.textSecondary)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteWorkout(workout)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func deleteWorkout(_ workout: Workout) {
        modelContext.delete(workout)
        try? modelContext.save()
        loadData()
    }

    // MARK: - Meals List

    private var mealsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Meals")
                    .font(.headline)
                Spacer()
                let unprocessedCount = (todayLog?.meals ?? []).filter { !$0.isProcessed }.count
                if unprocessedCount > 0 {
                    Button {
                        Task { await processAll() }
                    } label: {
                        Label("Process All (\(unprocessedCount))", systemImage: "sparkles")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.12))
                            .foregroundStyle(.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(processingMealId != nil)
                }
            }

            if let err = processingError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }

            if let meals = todayLog?.meals, !meals.isEmpty {
                let sorted = meals.sorted { $0.timestamp < $1.timestamp }
                ForEach(sorted, id: \.id) { meal in
                    MealRow(
                        meal: meal,
                        isProcessing: processingMealId == meal.id,
                        isAnyProcessingActive: processingMealId != nil,
                        onProcess: { Task { await processMeal(meal) } },
                        onDelete: { deleteMeal(meal) }
                    )
                    if meal.id != sorted.last?.id {
                        Divider()
                    }
                }
            } else {
                emptyMealsState
            }
        }
        .padding()
        .background(FuelTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func processMeal(_ meal: Meal) async {
        guard let settings else { return }
        processingMealId = meal.id
        processingError = nil
        let engine = NutritionEngine(modelContext: modelContext)
        do {
            try await engine.processMeal(meal, apiKey: settings.apiKey)
        } catch {
            processingError = error.localizedDescription
        }
        processingMealId = nil
    }

    private func deleteMeal(_ meal: Meal) {
        let engine = NutritionEngine(modelContext: modelContext)
        try? engine.deleteMeal(meal)
        loadData()
    }

    private func processAll() async {
        guard let log = todayLog else { return }
        let unprocessed = log.meals.filter { !$0.isProcessed }
        for meal in unprocessed {
            await processMeal(meal)
        }
    }

    private var emptyMealsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.largeTitle)
                .foregroundStyle(FuelTheme.textSecondary)
            Text("No meals logged yet")
                .font(.subheadline)
                .foregroundStyle(FuelTheme.textSecondary)
            Button("Log your first meal") {
                showLogMeal = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Data Loading

    private func loadData() {
        let engine = NutritionEngine(modelContext: modelContext)
        todayLog = try? engine.todayLog()
        settings = try? engine.settings()

        guard let log = todayLog, let settings else { return }
        let rm = ReminderManager.shared
        rm.reschedule(log: log, settings: settings)

        // Streak credit goes to yesterday's completion, not today's current state.
        // Passing today's meal count would reset the streak every morning before breakfast.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        let yesterdayLog = try? NutritionEngine(modelContext: modelContext).dayLog(for: yesterday)
        rm.updateStreak(yesterdayHadMeals: !(yesterdayLog?.meals.isEmpty ?? true))

        if settings.geofenceEnabled, let coord = settings.kitchenCoordinate {
            rm.startGeofence(latitude: coord.latitude, longitude: coord.longitude)
        }

        if morningBriefEnabled, !settings.apiKey.isEmpty {
            Task { await loadBrief(settings: settings) }
        }

        loadInsightIfNeeded()
    }

    private func loadBrief(settings: UserSettings) async {
        guard todayBrief == nil, !isGeneratingBrief else { return }
        // Set flag immediately — before any suspension point — to prevent concurrent calls
        isGeneratingBrief = true
        defer { isGeneratingBrief = false }
        todayBrief = try? await CoachService().generateBriefIfNeeded(
            modelContext: modelContext,
            settings: settings
        )
    }

    private func applyBriefTargets(calories: Int, protein: Int) {
        guard let settings else { return }
        settings.calorieTarget = calories
        settings.proteinTarget = protein
        try? modelContext.save()
    }
}
