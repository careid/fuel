import SwiftUI

struct AskCoachView: View {
    let onAsk: (String) async -> String

    @State private var question = ""
    @State private var answer: String?
    @State private var isAsking = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            VStack(alignment: .leading, spacing: 4) {
                Text("Ask Coach")
                    .font(.headline)
                Text("Ask anything about what to eat next.")
                    .font(.caption)
                    .foregroundStyle(FuelTheme.textSecondary)
            }

            HStack(spacing: 10) {
                TextField(
                    "e.g. What should I have for dinner?",
                    text: $question,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .focused($isFocused)
                .disabled(isAsking)

                Button {
                    Task { await submitQuestion() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSubmit ? Color.purple : FuelTheme.textSecondary)
                }
                .disabled(!canSubmit || isAsking)
                .buttonStyle(.plain)
            }

            if isAsking {
                HStack(spacing: 10) {
                    ProgressView().tint(.purple)
                    Text("Coach is thinking...")
                        .font(.subheadline)
                        .foregroundStyle(FuelTheme.textSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let answer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill.questionmark")
                            .font(.caption)
                            .foregroundStyle(.purple)
                        Text("Coach")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.purple)
                    }
                    Text(answer)
                        .font(.subheadline)
                        .foregroundStyle(FuelTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color.purple.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text("Responses are suggestions only — no meal is saved.")
                .font(.caption2)
                .foregroundStyle(FuelTheme.textSecondary)
        }
    }

    private var canSubmit: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitQuestion() async {
        guard canSubmit else { return }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        isFocused = false
        isAsking = true
        answer = nil
        answer = await onAsk(trimmed)
        isAsking = false
    }
}
