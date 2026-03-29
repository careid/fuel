import SwiftUI
import SwiftData

struct LogWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedCategory: WorkoutCategory = .running
    @State private var durationMinutes: Int = 30
    @State private var caloriesBurned: String = ""
    @State private var notes: String = ""
    @State private var selectedDate: Date = .now
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout Type") {
                    workoutTypePicker
                }

                Section("Details") {
                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 5...300, step: 5)

                    HStack {
                        Text("Calories Burned")
                        Spacer()
                        TextField("Optional", text: $caloriesBurned)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                Section("Date") {
                    DatePicker("Date", selection: $selectedDate, in: ...Date.now, displayedComponents: .date)
                }

                Section("Notes") {
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Save Failed", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Type Picker

    private var workoutTypePicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
            ForEach(WorkoutCategory.allCases, id: \.self) { cat in
                Button {
                    selectedCategory = cat
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: cat.icon)
                            .font(.title2)
                        Text(cat.label)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selectedCategory == cat
                            ? Color.purple.opacity(0.15)
                            : Color(.tertiarySystemBackground)
                    )
                    .foregroundStyle(selectedCategory == cat ? .purple : FuelTheme.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Save

    private func save() {
        let calories = Int(caloriesBurned.trimmingCharacters(in: .whitespaces))
        let workout = Workout(
            timestamp: selectedDate,
            category: selectedCategory,
            durationMinutes: durationMinutes,
            caloriesBurned: calories,
            notes: notes.isEmpty ? nil : notes
        )

        let engine = NutritionEngine(modelContext: modelContext)
        do {
            let log = try engine.dayLogOrCreate(for: selectedDate)
            log.workouts.append(workout)
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
            return
        }

        dismiss()
    }
}
