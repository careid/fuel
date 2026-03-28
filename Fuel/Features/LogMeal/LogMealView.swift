import SwiftUI

struct LogMealView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var inputText = ""
    @State private var selectedMealType: MealType = .lunch
    @State private var selectedDate: Date = .now
    @State private var isExtracting = false
    @State private var extractionResult: ExtractionResult?
    @State private var error: String?
    @State private var refinementText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let result = extractionResult {
                    reviewView(result)
                } else {
                    inputView
                }
            }
            .navigationTitle("Log Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Input View

    private var inputView: some View {
        VStack(spacing: 20) {
            mealTypePicker

            HStack {
                Text("Date")
                    .font(.subheadline)
                    .foregroundStyle(FuelTheme.textSecondary)
                Spacer()
                DatePicker("", selection: $selectedDate, in: ...Date.now, displayedComponents: .date)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What did you eat?")
                    .font(.headline)

                TextField(
                    "e.g. Ensure Max, 2 eggs, chipotle bowl chicken",
                    text: $inputText,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            inputActions
        }
        .padding()
    }

    private var mealTypePicker: some View {
        HStack(spacing: 12) {
            ForEach(MealType.allCases, id: \.self) { type in
                Button {
                    selectedMealType = type
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: type.icon)
                            .font(.title3)
                        Text(type.label)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selectedMealType == type
                            ? FuelTheme.calorieColor.opacity(0.15)
                            : FuelTheme.backgroundSecondary
                    )
                    .foregroundStyle(
                        selectedMealType == type
                            ? FuelTheme.calorieColor
                            : FuelTheme.textSecondary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var inputActions: some View {
        VStack(spacing: 12) {
            Button {
                Task { await extract() }
            } label: {
                HStack {
                    if isExtracting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isExtracting ? "Analyzing..." : "Analyze with Claude")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(inputText.isEmpty ? Color.gray : FuelTheme.calorieColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(inputText.isEmpty || isExtracting)

            Button {
                Task { await saveRaw() }
            } label: {
                Text("Save Entry")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(FuelTheme.backgroundSecondary)
                    .foregroundStyle(inputText.isEmpty ? FuelTheme.textSecondary : FuelTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(inputText.isEmpty || isExtracting)

            Text("Analyze now for macros, or save the entry and process later")
                .font(.caption)
                .foregroundStyle(FuelTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Review View

    private func reviewView(_ result: ExtractionResult) -> some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(result.items.enumerated()), id: \.offset) { _, item in
                        extractedItemRow(item)
                    }

                    if let notes = result.notes, !notes.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(FuelTheme.textSecondary)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    summaryRow(result)

                    refinementInput
                }
                .padding()
            }

            confirmButton
                .padding(.horizontal)
                .padding(.bottom)
        }
    }

    private func extractedItemRow(_ item: ExtractedItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(item.quantity)
                    .font(.caption)
                    .foregroundStyle(FuelTheme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.calories) cal")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack(spacing: 8) {
                    Text("\(Int(item.proteinGrams))g P")
                        .foregroundStyle(FuelTheme.proteinColor)
                    Text("\(Int(item.carbsGrams))g C")
                        .foregroundStyle(FuelTheme.carbsColor)
                    Text("\(Int(item.fatGrams))g F")
                        .foregroundStyle(FuelTheme.fatColor)
                }
                .font(.caption)
            }
        }
        .padding()
        .background(FuelTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func summaryRow(_ result: ExtractionResult) -> some View {
        let totalCal = result.items.reduce(0) { $0 + $1.calories }
        let totalProtein = result.items.reduce(0) { $0 + $1.proteinGrams }

        return HStack {
            Text("Total")
                .font(.headline)
            Spacer()
            Text("\(totalCal) cal  ·  \(Int(totalProtein))g protein")
                .font(.headline)
        }
        .padding()
    }

    private var refinementInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Need to correct something?")
                .font(.caption)
                .foregroundStyle(FuelTheme.textSecondary)

            HStack {
                TextField("e.g. \"actually 8oz salmon\"", text: $refinementText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await refine() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(FuelTheme.calorieColor)
                }
                .disabled(refinementText.isEmpty || isExtracting)
            }
        }
    }

    private var confirmButton: some View {
        Button {
            Task { await saveMeal() }
        } label: {
            Text("Save Meal")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .fontWeight(.semibold)
        }
    }

    // MARK: - Actions

    private func extract() async {
        isExtracting = true
        error = nil

        do {
            let engine = NutritionEngine(modelContext: modelContext)
            let settings = try engine.settings()
            let result = try await ClaudeService().extractMeal(
                from: inputText,
                apiKey: settings.apiKey
            )
            extractionResult = result
        } catch {
            self.error = error.localizedDescription
        }

        isExtracting = false
    }

    private func refine() async {
        guard let current = extractionResult else { return }
        isExtracting = true

        do {
            let engine = NutritionEngine(modelContext: modelContext)
            let settings = try engine.settings()
            let result = try await ClaudeService().refineMeal(
                originalItems: current.items,
                refinement: refinementText,
                apiKey: settings.apiKey
            )
            extractionResult = result
            refinementText = ""
        } catch {
            self.error = error.localizedDescription
        }

        isExtracting = false
    }

    private func saveRaw() async {
        let engine = NutritionEngine(modelContext: modelContext)
        do {
            _ = try engine.saveRawMeal(text: inputText, mealType: selectedMealType, date: selectedDate)
        } catch {
            self.error = error.localizedDescription
            return
        }
        dismiss()
    }

    private func saveMeal() async {
        guard let result = extractionResult else { return }

        let engine = NutritionEngine(modelContext: modelContext)
        let foodItems = result.items.map { item in
            FoodItem(
                name: item.name,
                calories: item.calories,
                proteinGrams: item.proteinGrams,
                carbsGrams: item.carbsGrams,
                fatGrams: item.fatGrams,
                quantity: item.quantity,
                confidence: Confidence(rawValue: item.confidence) ?? .medium
            )
        }

        let meal = Meal(
            timestamp: selectedDate,
            mealType: selectedMealType,
            items: foodItems,
            inputType: .text,
            rawInputText: inputText
        )

        do {
            let log = try engine.dayLogOrCreate(for: selectedDate)
            log.meals.append(meal)
            try modelContext.save()
        } catch {
            self.error = error.localizedDescription
            return
        }

        dismiss()
    }
}
