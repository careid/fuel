import SwiftUI

struct MacroProgressBar: View {
    let label: String
    let current: Double
    let target: Double
    let unit: String
    let color: Color

    private var ratio: Double {
        target > 0 ? current / target : 0
    }

    private var percentage: Int {
        Int(ratio * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(FuelTheme.textSecondary)
                Spacer()
                Text("\(Int(current)) / \(Int(target))\(unit)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(FuelTheme.textPrimary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color.opacity(0.15))

                    RoundedRectangle(cornerRadius: 6)
                        .fill(color)
                        .frame(width: min(geometry.size.width * ratio, geometry.size.width))
                        .animation(.spring(duration: 0.4), value: ratio)
                }
            }
            .frame(height: 12)

            Text("\(percentage)%")
                .font(.caption2)
                .foregroundStyle(FuelTheme.textSecondary)
        }
    }
}
