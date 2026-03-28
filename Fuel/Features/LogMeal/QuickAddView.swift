import SwiftUI
import SwiftData

struct QuickAddView: View {
    let onSelect: (String, MealType) -> Void

    @Query(sort: \Meal.timestamp, order: .reverse)
    private var allMeals: [Meal]

    // Deduplicated recent entries (last 10 unique raw texts)
    private var recent: [(text: String, mealType: MealType, calories: Int?)] {
        var seen = Set<String>()
        var result: [(text: String, mealType: MealType, calories: Int?)] = []
        for meal in allMeals {
            guard let text = meal.rawInputText, !text.isEmpty else { continue }
            let key = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append((
                text: text,
                mealType: meal.mealType,
                calories: meal.isProcessed ? meal.totalCalories : nil
            ))
            if result.count == 10 { break }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if recent.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.largeTitle)
                        .foregroundStyle(FuelTheme.textSecondary)
                    Text("No recent entries yet")
                        .foregroundStyle(FuelTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                Text("Tap any entry to re-log it")
                    .font(.caption)
                    .foregroundStyle(FuelTheme.textSecondary)

                ForEach(recent, id: \.text) { entry in
                    Button { onSelect(entry.text, entry.mealType) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: entry.mealType.icon)
                                .font(.title3)
                                .foregroundStyle(FuelTheme.calorieColor)
                                .frame(width: 28)

                            Text(entry.text)
                                .font(.subheadline)
                                .foregroundStyle(FuelTheme.textPrimary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if let cal = entry.calories {
                                Text("\(cal) cal")
                                    .font(.caption)
                                    .foregroundStyle(FuelTheme.textSecondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(FuelTheme.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
