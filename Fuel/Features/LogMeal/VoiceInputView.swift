import SwiftUI

struct VoiceInputView: View {
    @Binding var transcript: String
    @StateObject private var speech = SpeechService()

    var body: some View {
        VStack(spacing: 20) {
            // Transcript / placeholder
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(FuelTheme.backgroundSecondary)
                    .frame(minHeight: 110)

                Group {
                    if speech.isRecording {
                        Text(speech.transcript.isEmpty ? "Listening…" : speech.transcript)
                            .foregroundStyle(speech.transcript.isEmpty ? FuelTheme.textSecondary : FuelTheme.textPrimary)
                    } else if transcript.isEmpty {
                        Text("Tap the mic and describe what you ate")
                            .foregroundStyle(FuelTheme.textSecondary)
                    } else {
                        Text(transcript)
                            .foregroundStyle(FuelTheme.textPrimary)
                    }
                }
                .font(.subheadline)
                .padding(14)
            }

            // Record button
            Button {
                Task { await toggleRecording() }
            } label: {
                ZStack {
                    Circle()
                        .fill(speech.isRecording ? Color.red : FuelTheme.calorieColor)
                        .frame(width: 68, height: 68)
                        .shadow(color: (speech.isRecording ? Color.red : FuelTheme.calorieColor).opacity(0.4),
                                radius: speech.isRecording ? 12 : 4)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                   value: speech.isRecording)

                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }

            if speech.permissionDenied {
                Text("Microphone or speech recognition access required.\nEnable in Settings.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .onChange(of: speech.isRecording) { _, recording in
            if !recording, !speech.transcript.isEmpty {
                transcript = speech.transcript
            }
        }
        .onDisappear {
            if speech.isRecording { speech.stopRecording() }
        }
    }

    private func toggleRecording() async {
        if speech.isRecording {
            speech.stopRecording()
        } else {
            let ok = await speech.requestPermissions()
            guard ok else { return }
            try? speech.startRecording()
        }
    }
}
