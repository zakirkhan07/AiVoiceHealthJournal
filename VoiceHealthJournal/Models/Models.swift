import Foundation
import SwiftData

/// A single daily check-in. Stores the raw transcript plus AI-extracted structured logs.
/// Extracted logs are user-editable — the AI's output is a draft, not the truth.
@Model
final class JournalEntry {
    var id: UUID
    var createdAt: Date
    var transcript: String
    var aiSummary: String?
    var moodScore: Int?          // 1–5, extracted or user-set
    var processingState: String  // ProcessingState.rawValue
    var lastError: String?

    @Relationship(deleteRule: .cascade) var symptoms: [SymptomLog]
    @Relationship(deleteRule: .cascade) var lifestyle: [LifestyleLog]

    init(transcript: String, createdAt: Date = .now) {
        self.id = UUID()
        self.createdAt = createdAt
        self.transcript = transcript
        self.symptoms = []
        self.lifestyle = []
        self.processingState = ProcessingState.pending.rawValue
    }

    var state: ProcessingState {
        get { ProcessingState(rawValue: processingState) ?? .pending }
        set { processingState = newValue.rawValue }
    }
}

enum ProcessingState: String, Codable {
    case pending      // recorded, not yet sent to AI
    case processing   // request in flight
    case done         // structured data extracted
    case failed       // extraction failed; retry available — transcript is never lost
}

@Model
final class SymptomLog {
    var id: UUID
    var name: String        // e.g. "headache"
    var severity: Int       // 1–5
    var note: String?
    var userEdited: Bool    // true once the user has corrected the AI

    init(name: String, severity: Int, note: String? = nil, userEdited: Bool = false) {
        self.id = UUID()
        self.name = name
        self.severity = severity
        self.note = note
        self.userEdited = userEdited
    }
}

@Model
final class LifestyleLog {
    var id: UUID
    var category: String    // "sleep", "food", "exercise", "stress", "other"
    var detail: String      // e.g. "slept 6 hours", "skipped lunch"
    var userEdited: Bool

    init(category: String, detail: String, userEdited: Bool = false) {
        self.id = UUID()
        self.category = category
        self.detail = detail
        self.userEdited = userEdited
    }
}

/// Codable mirror of what we ask the LLM to return. Kept separate from SwiftData models
/// so a schema change in the prompt never corrupts persisted data.
struct ExtractionResult: Codable {
    struct Symptom: Codable {
        let name: String
        let severity: Int
        let note: String?
    }
    struct Lifestyle: Codable {
        let category: String
        let detail: String
    }
    let summary: String
    let moodScore: Int?
    let symptoms: [Symptom]
    let lifestyle: [Lifestyle]
}
