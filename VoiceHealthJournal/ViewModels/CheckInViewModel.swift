import Foundation
import SwiftData

/// Orchestrates the check-in flow. Key invariant: the transcript is persisted
/// IMMEDIATELY on save, before any network call. AI extraction enriches the
/// entry afterward and can fail/retry without ever losing user data.
@MainActor
final class CheckInViewModel: ObservableObject {

    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var lastErrorRetryable = false
    @Published var lastSavedEntry: JournalEntry?

    func save(transcript: String, context: ModelContext) async {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Nothing to save yet — record or type your check-in first."
            return
        }
        errorMessage = nil

        // 1. Persist first. This can't fail on network.
        let entry = JournalEntry(transcript: trimmed)
        context.insert(entry)
        try? context.save()
        lastSavedEntry = entry
        AnalyticsLogger.shared.log(.checkInSaved, props: ["chars": "\(trimmed.count)"])

        // 2. Then extract.
        await runExtraction(for: entry, context: context)
    }

    func retry(entry: JournalEntry, context: ModelContext) async {
        AnalyticsLogger.shared.log(.extractionRetried)
        await runExtraction(for: entry, context: context)
    }

    private func runExtraction(for entry: JournalEntry, context: ModelContext) async {
        isProcessing = true
        entry.state = .processing
        entry.lastError = nil
        try? context.save()

        let apiKey = UserDefaults.standard.string(forKey: "anthropic_api_key")

        do {
            let result = try await AIService.shared.extract(from: entry.transcript, apiKey: apiKey)
            apply(result, to: entry)
            entry.state = .done
            AnalyticsLogger.shared.log(.extractionSucceeded,
                                       props: ["symptoms": "\(result.symptoms.count)"])
        } catch let error as AIError {
            entry.state = .failed
            entry.lastError = error.errorDescription
            errorMessage = error.errorDescription
            lastErrorRetryable = error.isRetryable
            AnalyticsLogger.shared.log(.extractionFailed, props: ["error": "\(error)"])
        } catch {
            entry.state = .failed
            entry.lastError = error.localizedDescription
            errorMessage = error.localizedDescription
            lastErrorRetryable = true
        }

        try? context.save()
        isProcessing = false
    }

    private func apply(_ result: ExtractionResult, to entry: JournalEntry) {
        entry.aiSummary = result.summary
        entry.moodScore = result.moodScore
        // Replace only AI-generated logs; never clobber user edits on retry.
        entry.symptoms.removeAll { !$0.userEdited }
        entry.lifestyle.removeAll { !$0.userEdited }
        entry.symptoms.append(contentsOf: result.symptoms.map {
            SymptomLog(name: $0.name, severity: min(max($0.severity, 1), 5), note: $0.note)
        })
        entry.lifestyle.append(contentsOf: result.lifestyle.map {
            LifestyleLog(category: $0.category, detail: $0.detail)
        })
    }
}
