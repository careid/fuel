import SwiftUI

struct MealRow: View {
    let meal: Meal
    var isProcessing: Bool = false
    var isAnyProcessingActive: Bool = false
    var onProcess: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if meal.isProcessed {
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
            } else {
                unprocessedRow
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Processed

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

            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Meal", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .padding(.leading, 44)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Unprocessed

    private var unprocessedRow: some View {
        HStack(spacing: 12) {
            Image(systemName: meal.mealType.icon)
                .font(.title3)
                .foregroundStyle(FuelTheme.textSecondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.mealType.label)
                    .font(.headline)
                    .foregroundStyle(FuelTheme.textSecondary)

                if let raw = meal.rawInputText, !raw.isEmpty {
                    Text(raw)
                        .font(.caption)
                        .foregroundStyle(FuelTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.trailing, 4)
            } else {
                HStack(spacing: 8) {
                    if let onProcess {
                        Button(action: onProcess) {
                            Label("Process", systemImage: "sparkles")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.purple.opacity(isAnyProcessingActive ? 0.06 : 0.12))
                                .foregroundStyle(isAnyProcessingActive ? FuelTheme.textSecondary : .purple)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(isAnyProcessingActive)
                    }

                    if let onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.subheadline)
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func confidenceColor(_ confidence: Confidence) -> Color {
        switch confidence {
        case .high: .green
        case .medium: .orange
        case .low: .red
        }
    }
}
