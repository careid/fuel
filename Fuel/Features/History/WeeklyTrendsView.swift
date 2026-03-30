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
        let today = DayLog.dateFormatter.string(from: .now)
        let cutoff = DayLog.dateFormatter.string(
            from: Calendar.current.date(byAdding: .day, value: -13, to: .now) ?? .now
        )
        return allDays.filter { $0.dateString >= cutoff && $0.dateString < today }
            .sorted { $0.dateString < $1.dateString }
    }

    private var last7Days: [DayLog] { Array(recentDays.suffix(7)) }

    private var snapshotsByDate: [String: HealthSnapshot] {
        Dictionary(allSnapshots.map { ($0.dateString, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var netCaloriesData: [(date: Date, netCal: Int)] {
        recentDays.map { day in
            let active = snapshotsByDate[day.dateString]?.activeCalories ?? 0
            return (date: day.date, netCal: day.totalCalories - (calorieTarget + active))
        }
    }

    private var stepsData: [(date: Date, steps: Int)] {
        recentDays.compactMap { day in
            guard let snap = snapshotsByDate[day.dateString],
                  let steps = snap.steps else { return nil }
            return (date: day.date, steps: steps)
        }
    }

    private var sleepData: [(date: Date, hours: Double)] {
        recentDays.compactMap { day in
            guard let snap = snapshotsByDate[day.dateString],
                  let hours = snap.sleepHours else { return nil }
            return (date: day.date, hours: hours)
        }
    }

    // Today's data — shown as ghost marks on charts but excluded from trend calculations.
    private var todayDayLog: DayLog? {
        let today = DayLog.dateFormatter.string(from: .now)
        return allDays.first { $0.dateString == today }
    }

    private var todaySnapshot: HealthSnapshot? {
        snapshotsByDate[DayLog.dateFormatter.string(from: .now)]
    }

    private var todayNetCalEntry: (date: Date, netCal: Int)? {
        guard let log = todayDayLog else { return nil }
        let active = todaySnapshot?.activeCalories ?? 0
        return (.now, log.totalCalories - (calorieTarget + active))
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
                    if stepsData.count >= 2 {
                        stepsChart
                    }
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
        chartCard(title: "Net Calories", subtitle: "surplus (+) or deficit (−) vs. goal") {
            Chart {
                ForEach(netCaloriesData, id: \.date) { entry in
                    BarMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Net Calories", entry.netCal)
                    )
                    .foregroundStyle(entry.netCal > 0 ? Color.orange : Color.green)
                    .cornerRadius(4)
                }

                if let today = todayNetCalEntry {
                    BarMark(
                        x: .value("Date", today.date, unit: .day),
                        y: .value("Net Calories", today.netCal)
                    )
                    .foregroundStyle((today.netCal > 0 ? Color.orange : Color.green).opacity(0.35))
                    .cornerRadius(4)
                }

                RuleMark(y: .value("Break Even", 0))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
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

                if let todayLog = todayDayLog {
                    BarMark(
                        x: .value("Date", Date.now, unit: .day),
                        y: .value("Protein (g)", todayLog.totalProtein)
                    )
                    .foregroundStyle(FuelTheme.progressColor(ratio: todayLog.totalProtein / Double(proteinTarget)).opacity(0.35))
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

    // MARK: - Steps Chart

    private var stepsChart: some View {
        chartCard(title: "Steps", subtitle: "daily activity") {
            Chart {
                ForEach(stepsData, id: \.date) { entry in
                    BarMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Steps", entry.steps)
                    )
                    .foregroundStyle(.green.opacity(0.75))
                    .cornerRadius(4)
                }

                if let snap = todaySnapshot, let steps = snap.steps {
                    BarMark(
                        x: .value("Date", Date.now, unit: .day),
                        y: .value("Steps", steps)
                    )
                    .foregroundStyle(Color.green.opacity(0.3))
                    .cornerRadius(4)
                }

                RuleMark(y: .value("Goal", 10_000))
                    .foregroundStyle(.green.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .topTrailing, alignment: .topTrailing) {
                        Text("10k")
                            .font(.caption2)
                            .foregroundStyle(.green)
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

                if let snap = todaySnapshot, let hours = snap.sleepHours {
                    PointMark(
                        x: .value("Date", Date.now, unit: .day),
                        y: .value("Sleep (h)", hours)
                    )
                    .foregroundStyle(Color.indigo.opacity(0.35))
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

        let poorCal = avgCaloriesForSleepDays(poor)
        let goodCal = avgCaloriesForSleepDays(good)
        guard poorCal > 0, goodCal > 0 else { return nil }

        if poorCal > goodCal + 150 {
            return "After poor sleep (<6.5h) you average \(poorCal - goodCal) more calories."
        } else if goodCal > poorCal + 150 {
            return "After good sleep (≥7.5h) you average \(goodCal - poorCal) more calories."
        }
        return nil
    }

    // Returns avg calories eaten on days matched by these sleep entries.
    // entry.date is the waking-up day (sleep is stored against the morning-after date),
    // so we look up calories on entry.date directly — no +1 offset needed.
    private func avgCaloriesForSleepDays(_ entries: [(date: Date, hours: Double)]) -> Int {
        let total = entries.compactMap { entry -> Int? in
            let dateStr = DayLog.dateFormatter.string(from: entry.date)
            return recentDays.first(where: { $0.dateString == dateStr })?.totalCalories
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
        let dayTuples = last7Days.map { day -> (dateString: String, protein: Double, calories: Int) in
            (dateString: day.dateString, protein: day.totalProtein, calories: day.totalCalories)
        }
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
