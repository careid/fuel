import SwiftUI

struct HealthStatsCard: View {
    let snapshot: HealthSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("Health")
                    .font(.headline)
                Spacer()
            }

            let tiles = buildTiles()
            if tiles.isEmpty {
                Text("No health data for today")
                    .font(.subheadline)
                    .foregroundStyle(FuelTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(tiles, id: \.label) { tile in
                        statTile(tile)
                    }
                }
            }
        }
        .padding()
        .background(FuelTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Tile model

    private struct Tile {
        let icon: String
        let label: String
        let value: String
        let color: Color
    }

    private func buildTiles() -> [Tile] {
        var tiles: [Tile] = []

        if let sleep = snapshot.sleepHours {
            tiles.append(Tile(icon: "moon.fill",       label: "Sleep",      value: String(format: "%.1fh", sleep), color: .indigo))
        }
        if let steps = snapshot.steps {
            tiles.append(Tile(icon: "figure.walk",     label: "Steps",      value: steps.formatted(),               color: .green))
        }
        if let cal = snapshot.activeCalories {
            tiles.append(Tile(icon: "flame.fill",      label: "Active Cal", value: "\(cal) cal",                    color: .orange))
        }
        if let lbs = snapshot.weightLbs {
            tiles.append(Tile(icon: "scalemass.fill",  label: "Weight",     value: String(format: "%.1f lb", lbs),  color: .blue))
        }
        if let rhr = snapshot.restingHeartRate {
            tiles.append(Tile(icon: "heart.fill",      label: "Resting HR", value: "\(Int(rhr)) bpm",               color: .red))
        }
        if let type = snapshot.workoutType, let mins = snapshot.workoutMinutes {
            let extra = snapshot.workoutCalories.map { " · \($0) cal" } ?? ""
            tiles.append(Tile(icon: "figure.run",      label: type,         value: "\(mins) min\(extra)",           color: .purple))
        }

        return tiles
    }

    private func statTile(_ tile: Tile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tile.icon)
                .font(.title3)
                .foregroundStyle(tile.color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(tile.label)
                    .font(.caption2)
                    .foregroundStyle(FuelTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(FuelTheme.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
