import SwiftUI

struct MealRow: View {
    let meal: Meal

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if isExpanded {
                itemList
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.vertical, 8)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: meal.mealType.icon)
                .font(.title3)
                .foregroundStyle(FuelTheme.calorieColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.mealType.label)
                    .font(.headline)

                Text(meal.items.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(FuelTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(meal.totalCalories) cal")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("\(Int(meal.totalProtein))g protein")
                    .font(.caption)
                    .foregroundStyle(FuelTheme.proteinColor)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(FuelTheme.textSecondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(meal.items, id: \.id) { item in
                HStack {
                    Circle()
                        .fill(confidenceColor(item.confidence))
                        .frame(width: 6, height: 6)

                    Text("\(item.quantity) \(item.name)")
                        .font(.caption)

                    Spacer()

                    Text("\(item.calories) cal")
                        .font(.caption)
                        .foregroundStyle(FuelTheme.textSecondary)

                    Text("\(Int(item.proteinGrams))g P")
                        .font(.caption)
                        .foregroundStyle(FuelTheme.proteinColor)
                }
            }
        }
        .padding(.leading, 44)
        .padding(.top, 8)
    }

    private func confidenceColor(_ confidence: Confidence) -> Color {
        switch confidence {
        case .high: .green
        case .medium: .orange
        case .low: .red
        }
    }
}
