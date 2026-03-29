import SwiftUI

struct DailyBriefCard: View {
    let brief: DailyBrief?
    let isLoading: Bool
    var onApplyTargets: ((Int, Int) -> Void)? = nil

    var body: some View {
        if isLoading {
            loadingCard
        } else if let brief {
            briefCard(brief)
        }
    }

    // MARK: - Loading State

    private var loadingCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.horizon.fill")
                .foregroundStyle(.orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Morning Brief")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                Text("Preparing your daily plan...")
                    .font(.subheadline)
                    .foregroundStyle(FuelTheme.textSecondary)
            }
            Spacer()
            ProgressView()
                .tint(.orange)
        }
        .padding()
        .background(briefBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Brief Card

    private func briefCard(_ brief: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header
            HStack(spacing: 8) {
                Image(systemName: "sun.horizon.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                Text("Morning Brief")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                Spacer()
                Text(generatedTimeLabel(brief.generatedAt))
                    .font(.caption2)
                    .foregroundStyle(FuelTheme.textSecondary)
            }

            // Main brief text
            Text(brief.brief)
                .font(.subheadline)
                .foregroundStyle(FuelTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Pattern alert (optional)
            if let alert = brief.patternAlert {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(.top, 2)
                    Text(alert)
                        .font(.caption)
                        .foregroundStyle(FuelTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Target suggestion (optional — show if at least one target is recommended)
            if brief.recommendedCalories != nil || brief.recommendedProtein != nil {
                let cal = brief.recommendedCalories
                let prot = brief.recommendedProtein
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suggested for today")
                            .font(.caption2)
                            .foregroundStyle(FuelTheme.textSecondary)
                        Group {
                            if let cal, let prot {
                                Text("\(cal) cal · \(prot)g protein")
                            } else if let cal {
                                Text("\(cal) cal")
                            } else if let prot {
                                Text("\(prot)g protein")
                            }
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(FuelTheme.textPrimary)
                    }
                    Spacer()
                    if let cal, let prot {
                        Button("Apply") {
                            onApplyTargets?(cal, prot)
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(briefBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private var briefBackground: some View {
        ZStack {
            FuelTheme.backgroundSecondary
            LinearGradient(
                colors: [Color.orange.opacity(0.08), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private func generatedTimeLabel(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}
