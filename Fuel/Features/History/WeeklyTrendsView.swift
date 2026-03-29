import SwiftUI
import Charts
import SwiftData

struct WeeklyTrendsView: View {
    @Query(sort: \DayLog.dateString, order: .reverse) private var allDays: [DayLog]
    @Query(sort: \HealthSnapshot.dateString, order: .reverse) private var allSnapshots: [HealthSnapshot]
    @Query private var settingsArr: [UserSettings]

    @State private var weeklyInsight: String?
    @State private var isLoadingWeeklyInsight = false
    @State private var weeklyInsightLoaded = false

    private var settings: UserSettings? { settingsArr.first }
    private var calorieTarget: Int { settings?.calorieTarget ?? 2200 }
    private var proteinTarget: Int { settings?.proteinTarget ?? 160 }

    private var recentDays: [DayLog] {
        let cutoff = DayLog.dateFormatter.string(
            from: Calendar.current.date(byAdding: .day, value: -13, to: .now) ?? .now
        )
        return allDays.filter { $0.dateString >= cutoff }.sorted { $0.dateString < $1.dateString }
    }

    private var last7Days: [DayLog] { Array(recentDays.suffix(7)) }

    private var snapshotsByDate: [String: HealthSnapshot] {
        Dictionary(uniqueKeysWithValues: allSnapshots.map { ($0.dateString, $0) })
    }

    private var sleepData: [(date: Date, hours: Double)] {
        recentDays.compactMap { day in
            guard let snap = snapshotsByDate[day.dateString],
                  let hours = snap.sleepHours else { return nil }
            return (date: day.date, hours: hours)
        }
    }

    var body: some View {
        ScrollView {
            if recentDays.isEmpty {
                ContentUnavailableView(
                    "No Data Yet",
                    systemImage: "chart.bar",
                    description: Text("Log meals for a few days to see your trends here.")
                )
                .padding(.top, 60)
            } else {
                VStack(spacing: 16) {
                    weeklyInsightCard
                    calorieChart
                    proteinChart
                    if sleepData.count >= 2 {
                        sleepChart
                    }
                }
                .padding()
                .task {
                    await loadWeeklyInsightIfNeeded()
                }
            }
        }
    }

    // MARK: - Calorie Chart

    private var calorieChart: some View {
        chartCard(title: "Calories", subtitle: "14-day history") {
            Chart {
                ForEach(recentDays, id: \.dateString) { day in
                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Calories", day.totalCalories)
                    )
                    .foregroundStyle(FuelTheme.progressColor(ratio: Double(day.totalCalories) / Double(calorieTarget)))
                    .cornerRadius(4)
                }

                RuleMark(y: .value("Target", calorieTarget))
                    .foregroundStyle(.orange.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .topTrailing, alignment: .topTrailing) {
                        Text("Goal")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.trailing, 4)
                    }
            }
            .chartXAxis { dateAxis() }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
            .frame(height: 150)
        }
    }

    // MARK: - Protein Chart

    private var proteinChart: some View {
        chartCard(title: "Protein", subtitle: "grams per day") {
            Chart {
                ForEach(recentDays, id: \.dateString) { day in
                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Protein (g)", day.totalProtein)
                    )
                    .foregroundStyle(FuelTheme.progressColor(ratio: day.totalProtein / Double(proteinTarget)))
                    .cornerRadius(4)
                }

                RuleMark(y: .value("Target", proteinTarget))
                    .foregroundStyle(.blue.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .topTrailing, alignment: .topTrailing) {
                        Text("Goal")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .padding(.trailing, 4)
                    }
            }
            .chartXAxis { dateAxis() }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
            .frame(height: 150)
        }
    }

    // MARK: - Sleep Chart

    private var sleepChart: some View {
        chartCard(title: "Sleep", subtitle: "hours per night") {
            Chart {
                ForEach(sleepData, id: \.date) { entry in
                    AreaMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Sleep (h)", entry.hours)
                    )
                    .foregroundStyle(.indigo.opacity(0.15))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Sleep (h)", entry.hours)
                    )
                    .foregroundStyle(.indigo)
                    .interpolationMethod(.catmullRom)
                    .symbol(Circle().strokeBorder(lineWidth: 2))
                    .symbolSize(40)
                }

                RuleMark(y: .value("Recommended", 8.0))
                    .foregroundStyle(.indigo.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .topTrailing, alignment: .topTrailing) {
                        Text("8h")
                            .font(.caption2)
                            .foregroundStyle(.indigo)
                            .padding(.trailing, 4)
                    }
            }
            .chartXAxis { dateAxis() }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 4, 6, 8, 10]) { value in
                    AxisValueLabel("\(value.as(Double.self).map { Int($0) } ?? 0)h")
                }
            }
            .chartYScale(domain: 0...max(10, sleepData.map(\.hours).max().map { $0 + 1 } ?? 10))
            .frame(height: 150)

            if let insight = sleepInsight {
                Text(insight)
                    .font(.caption)
                    .foregroundStyle(FuelTheme.textSecondary)
                    .padding(.top, 6)
            }
        }
    }

    private var sleepInsight: String? {
        guard sleepData.count >= 4 else { return nil }
        let poor = sleepData.filter { $0.hours < 6.5 }
        let good = sleepData.filter { $0.hours >= 7.5 }
        guard !poor.isEmpty, !good.isEmpty else { return nil }

        let poorCal = poorDayCals(for: poor)
        let goodCal = poorDayCals(for: good)
        guard poorCal > 0, goodCal > 0 else { return nil }

        if poorCal > goodCal + 150 {
            return "After poor sleep (<6.5h) you average \(poorCal - goodCal) more calories."
        } else if goodCal > poorCal + 150 {
            return "After good sleep (≥7.5h) you average \(goodCal - poorCal) more calories."
        }
        return nil
    }

    private func poorDayCals(for entries: [(date: Date, hours: Double)]) -> Int {
        let cal = Calendar.current
        let total = entries.compactMap { entry -> Int? in
            guard let nextDay = cal.date(byAdding: .day, value: 1, to: entry.date) else { return nil }
            let nextStr = DayLog.dateFormatter.string(from: nextDay)
            return recentDays.first(where: { $0.dateString == nextStr })?.totalCalories
        }.reduce(0, +)
        return entries.isEmpty ? 0 : total / entries.count
    }

    // MARK: - Weekly Insight Card

    @ViewBuilder
    private var weeklyInsightCard: some View {
        if isLoadingWeeklyInsight {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.purple)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Pattern")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple)
                    Text("Analyzing your week...")
                        .font(.subheadline)
                        .foregroundStyle(FuelTheme.textSecondary)
                }
                Spacer()
                ProgressView().tint(.purple)
            }
            .padding()
            .background(weeklyInsightBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if let insight = weeklyInsight {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(.purple)
                        .font(.title3)
                    Text("Weekly Pattern")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple)
                }
                Text(insight)
                    .font(.subheadline)
                    .foregroundStyle(FuelTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(weeklyInsightBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var weeklyInsightBackground: some View {
        ZStack {
            FuelTheme.backgroundSecondary
            LinearGradient(
                colors: [Color.purple.opacity(0.07), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func loadWeeklyInsightIfNeeded() async {
        guard !weeklyInsightLoaded, last7Days.count >= 3,
              let settings, !settings.apiKey.isEmpty else { return }
        weeklyInsightLoaded = true
        isLoadingWeeklyInsight = true
        defer { isLoadingWeeklyInsight = false }
        let dayTuples = last7Days.map { (dateString: $0.dateString, protein: $0.totalProtein, calories: $0.totalCalories) }
        do {
            weeklyInsight = try await ClaudeService().generateWeeklyInsight(
                days: dayTuples,
                proteinTarget: proteinTarget,
                calorieTarget: calorieTarget,
                apiKey: settings.apiKey
            )
        } catch {
            weeklyInsight = nil
            weeklyInsightLoaded = false
        }
    }

    // MARK: - Helpers

    @AxisContentBuilder
    private func dateAxis() -> some AxisContent {
        AxisMarks(values: .stride(by: .day, count: recentDays.count <= 7 ? 1 : 2)) { _ in
            AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true)
        }
    }

    private func chartCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(FuelTheme.textSecondary)
            }
            content()
        }
        .padding()
        .background(FuelTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
