import SwiftUI

enum FuelTheme {
    // MARK: - Colors

    static let calorieColor = Color.orange
    static let proteinColor = Color.blue
    static let carbsColor = Color.green
    static let fatColor = Color.yellow

    static let backgroundPrimary = Color(.systemBackground)
    static let backgroundSecondary = Color(.secondarySystemBackground)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)

    // MARK: - Progress Bar

    static func progressColor(ratio: Double) -> Color {
        switch ratio {
        case ..<0.5: .red
        case 0.5..<0.8: .orange
        case 0.8..<1.05: .green
        default: .purple // over target
        }
    }
}
