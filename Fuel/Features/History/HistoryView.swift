import SwiftUI
import SwiftData

private enum HistoryTab: String, CaseIterable {
    case calendar = "Calendar"
    case trends = "Trends"
}

struct HistoryView: View {
    @Query(sort: \DayLog.dateString, order: .reverse) private var allDays: [DayLog]
    @Query(sort: \HealthSnapshot.dateString, order: .reverse) private var allSnapshots: [HealthSnapshot]
    @State private var selectedTab: HistoryTab = .calendar
    @State private var displayedMonth: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
    }()

    private var daysByDateString: [String: DayLog] {
        Dictionary(allDays.map { ($0.dateString, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var snapshotsByDate: [String: HealthSnapshot] {
        Dictionary(allSnapshots.map { ($0.dateString, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(displayedMonth, equalTo: .now, toGranularity: .month)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(HistoryTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider()

                switch selectedTab {
                case .calendar:
                    calendarSection
                case .trends:
                    WeeklyTrendsView()
                }
            }
            .navigationTitle("History")
        }
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthHeader
                    .padding(.horizontal)

                calendarGrid
                    .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                recentList
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
            .padding(.top, 12)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                step(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(FuelTheme.textPrimary)
            }

            Spacer()

            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)

            Spacer()

            Button {
                step(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundStyle(isCurrentMonth ? FuelTheme.textSecondary : FuelTheme.textPrimary)
            }
            .disabled(isCurrentMonth)
        }
    }

    private var calendarGrid: some View {
        let days = calendarDays()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        return VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(weekdayHeaders, id: \.self) { sym in
                    Text(sym)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(FuelTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let dateStr = DayLog.dateFormatter.string(from: date)
                        let dayLog = daysByDateString[dateStr]
                        let isToday = Calendar.current.isDateInToday(date)

                        if let dayLog {
                            NavigationLink(destination: DayDetailView(dayLog: dayLog)) {
                                calendarCell(date: date, hasData: true, isToday: isToday)
                            }
                            .buttonStyle(.plain)
                        } else {
                            calendarCell(date: date, hasData: false, isToday: isToday)
                        }
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    private func calendarCell(date: Date, hasData: Bool, isToday: Bool) -> some View {
        let day = Calendar.current.component(.day, from: date)
        return VStack(spacing: 3) {
            Text("\(day)")
                .font(.subheadline)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(
                    isToday ? .white
                    : (hasData ? FuelTheme.textPrimary : FuelTheme.textSecondary.opacity(0.5))
                )

            Circle()
                .fill(hasData && !isToday ? FuelTheme.calorieColor : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isToday ? FuelTheme.calorieColor : (hasData ? FuelTheme.calorieColor.opacity(0.1) : Color.clear))
        )
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Days")
                .font(.headline)
                .padding(.bottom, 12)

            if allDays.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "calendar",
                    description: Text("Your meal history will appear here as you log meals.")
                )
            } else {
                let recent = Array(allDays.prefix(10))
                ForEach(Array(recent.enumerated()), id: \.element.dateString) { idx, day in
                    NavigationLink(destination: DayDetailView(dayLog: day)) {
                        dayRow(day)
                    }
                    .buttonStyle(.plain)

                    if idx < recent.count - 1 {
                        Divider().padding(.leading, 4)
                    }
                }
            }
        }
        .padding()
        .background(FuelTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func dayRow(_ day: DayLog) -> some View {
        let activeCalories = snapshotsByDate[day.dateString]?.activeCalories ?? 0
        let netCalories = day.totalCalories - activeCalories
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(FuelTheme.textPrimary)
                Text("\(day.meals.count) meal\(day.meals.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(FuelTheme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(activeCalories > 0 ? "net \(netCalories) cal" : "\(day.totalCalories) cal")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(FuelTheme.calorieColor)
                Text("\(Int(day.totalProtein))g protein")
                    .font(.caption)
                    .foregroundStyle(FuelTheme.proteinColor)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Calendar Helpers

    private func step(by months: Int) {
        let cal = Calendar.current
        if let next = cal.date(byAdding: .month, value: months, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private func calendarDays() -> [Date?] {
        let cal = Calendar.current
        guard let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth)),
              let dayCount = cal.range(of: .day, in: .month, for: firstOfMonth)?.count else { return [] }

        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        let leadingPads = (firstWeekday - cal.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingPads)
        for i in 0..<dayCount {
            days.append(cal.date(byAdding: .day, value: i, to: firstOfMonth))
        }
        return days
    }

    private var weekdayHeaders: [String] {
        let cal = Calendar.current
        let symbols = cal.shortStandaloneWeekdaySymbols.map { String($0.prefix(2)) }
        let offset = cal.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
}
