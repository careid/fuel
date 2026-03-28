import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \DayLog.dateString, order: .reverse) private var allDays: [DayLog]

    var body: some View {
        NavigationStack {
            List {
                if allDays.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "calendar",
                        description: Text("Your meal history will appear here as you log meals.")
                    )
                } else {
                    ForEach(allDays, id: \.dateString) { day in
                        NavigationLink(destination: DayDetailView(dayLog: day)) {
                            dayRow(day)
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private func dayRow(_ day: DayLog) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.headline)
                Text("\(day.meals.count) meal\(day.meals.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(FuelTheme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(day.totalCalories) cal")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("\(Int(day.totalProtein))g protein")
                    .font(.caption)
                    .foregroundStyle(FuelTheme.proteinColor)
            }
        }
    }
}
