import SwiftUI
import SwiftData

struct TodayView: View {
    @Binding var showLogMeal: Bool
    @Environment(\.modelContext) private var modelContext

    @State private var todayLog: DayLog?
    @State private var settings: UserSettings?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    dailySummaryCard
                    mealsList
                    claudeInsightCard
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
            .onAppear(perform: loadData)
            .onChange(of: showLogMeal) { _, isShowing in
                if !isShowing { loadData() }
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
                target: Double(settings?.calorieTarget ?? 2200),
                unit: "",
                color: FuelTheme.calorieColor
            )

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

    // MARK: - Meals List

    private var mealsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Meals")
                    .font(.headline)
                Spacer()
            }

            if let meals = todayLog?.meals, !meals.isEmpty {
                let sorted = meals.sorted { $0.timestamp < $1.timestamp }
                ForEach(sorted, id: \.id) { meal in
                    MealRow(meal: meal)
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

    // MARK: - Claude Insight

    private var claudeInsightCard: some View {
        Group {
            if let log = todayLog, !log.meals.isEmpty, let settings {
                let proteinGap = Double(settings.proteinTarget) - log.totalProtein
                if proteinGap > 20 {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                        Text("You're \(Int(proteinGap))g short on protein. A protein shake or chicken dinner would close the gap.")
                            .font(.subheadline)
                            .foregroundStyle(FuelTheme.textSecondary)
                    }
                    .padding()
                    .background(Color.purple.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        let engine = NutritionEngine(modelContext: modelContext)
        todayLog = try? engine.todayLog()
        settings = try? engine.settings()
    }
}
