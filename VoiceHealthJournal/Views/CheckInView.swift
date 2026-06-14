import SwiftUI
import SwiftData

/// The core flow: record (or type) → live transcript → save → AI processes.
/// Every failure state has a visible, recoverable path.
struct CheckInView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var speech = SpeechService()
    @StateObject private var viewModel = CheckInViewModel()
    @State private var editableTranscript = ""
    @State private var showSavedToast = false

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.l) {

                // Permission / availability states get explicit UI, not silent failure.
                switch speech.state {
                case .denied(let reason), .unavailable(let reason):
                    StatusBanner(kind: .error, message: reason)
                default:
                    EmptyView()
                }

                if let error = viewModel.errorMessage, let entry = viewModel.lastSavedEntry, entry.state == .failed {
                    StatusBanner(kind: .error, message: error,
                                 retry: viewModel.lastErrorRetryable ? { Task { await viewModel.retry(entry: entry, context: context) } } : nil)
                }

                Spacer()

                if speech.state == .recording {
                    WaveformView(level: speech.audioLevel)
                        .frame(height: 70)
                        .padding(.horizontal)
                }

                ScrollView {
                    TextEditor(text: $editableTranscript)
                        .frame(minHeight: 140)
                        .padding(DS.Spacing.s)
                        .scrollContentBackground(.hidden)
                        .background(DS.Colors.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .topLeading) {
                            if editableTranscript.isEmpty && speech.state != .recording {
                                Text("Tap the mic and talk about your day — symptoms, sleep, food, stress. Or just type here.")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                                    .padding(DS.Spacing.m)
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityLabel("Check-in text")
                }
                .frame(maxHeight: 220)
                .padding(.horizontal)

                recordButton

                Button {
                    let text = editableTranscript
                    editableTranscript = ""
                    Task {
                        await viewModel.save(transcript: text, context: context)
                        if viewModel.lastSavedEntry?.state == .done {
                            showSavedToast = true
                        }
                    }
                } label: {
                    if viewModel.isProcessing {
                        HStack(spacing: DS.Spacing.s) {
                            ProgressView().tint(.white)
                            Text("Understanding your check-in…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Save check-in").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Colors.accent)
                .controlSize(.large)
                .disabled(editableTranscript.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isProcessing)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Daily check-in")
            .onChange(of: speech.transcript) { _, new in
                if !new.isEmpty { editableTranscript = new }
            }
            .sensoryFeedback(.success, trigger: showSavedToast)
            .overlay(alignment: .top) {
                if showSavedToast {
                    Text("Saved ✓")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(DS.Colors.positive, in: Capsule())
                        .foregroundStyle(.white)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { showSavedToast = false }
                        }
                }
            }
        }
    }

    private var recordButton: some View {
        Button {
            Task {
                if speech.state == .recording {
                    speech.stop()
                } else {
                    let ok = await speech.requestPermissions()
                    if ok { try? speech.start() }
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(speech.state == .recording ? DS.Colors.danger : DS.Colors.accent)
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                Image(systemName: speech.state == .recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel(speech.state == .recording ? "Stop recording" : "Start recording")
        .disabled({ if case .denied = speech.state { return true } else { return false } }())
    }
}
