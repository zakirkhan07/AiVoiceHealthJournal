# Voice Health Journal

A SwiftUI iOS app for people managing chronic symptoms: speak (or type) a daily
check-in, AI turns it into structured symptom & lifestyle logs, weekly insights
surface patterns, and a one-tap PDF brings your story to your doctor.


## Features

- 🎙 **Voice check-ins** — live on-device transcription (SFSpeechRecognizer) with an animated waveform; typing always works as fallback
- 🤖 **AI extraction** — transcript → structured JSON (symptoms w/ severity, lifestyle, mood, summary) via the Anthropic API with strict parsing, timeouts, retries with backoff, and typed errors
- ✏️ **Editable AI output** — users correct severities; edits are flagged and never overwritten on retry (trust through editability)
- 📈 **Insights** — mood trend line, symptom-frequency bars (Swift Charts), and Apple Health passive signals (steps, sleep, resting HR)
- 🩺 **Doctor report** — chronological PDF export via share sheet
- 🔔 **Daily reminder** — local notification at a chosen hour
- ♿️ **Accessibility** — VoiceOver labels on charts/controls, Dynamic Type-friendly layouts

## Setup

1. Xcode 15+, iOS 17+ target. Create a new iOS App project named `VoiceHealthJournal` (SwiftUI, Swift) and drop these source folders in.
2. **Capabilities**: add HealthKit.
3. **Info.plist keys** (required or the app crashes on first record):
   - `NSMicrophoneUsageDescription` — "We use the microphone for your voice check-ins."
   - `NSSpeechRecognitionUsageDescription` — "We transcribe your check-ins on this device."
   - `NSHealthShareUsageDescription` — "We read steps, sleep, and heart rate to enrich your insights."
4. Run, open **Settings** in the app, paste an Anthropic API key. (Without a key, check-ins still save as plain entries — graceful degradation.)

⚠️ **API key note**: the key is stored in UserDefaults and called directly from the device — fine for a demo, never for production. Production design: a thin backend proxy holds the key, authenticates the user, rate-limits, and logs.

## Architecture

```
Views (SwiftUI)  →  ViewModels (@MainActor, ObservableObject)  →  Services
                          ↓
                   SwiftData models (JournalEntry, SymptomLog, LifestyleLog)
```

Key decisions (and why):

- **Persist before network.** A check-in is saved to SwiftData *before* the AI call. Network failure can never lose what the user said. The entry carries a `ProcessingState` (pending/processing/done/failed) so the UI shows exactly where it stands and offers retry.
- **Codable mirror for AI output.** `ExtractionResult` is a separate Codable struct from the SwiftData models, so prompt/schema changes can't corrupt persisted data. Model output is treated as untrusted input: fences stripped, severity clamped to 1–5, decode failures become a typed, retryable error.
- **Typed errors → specific UI.** `AIError` distinguishes no-key / timeout / server / unparseable, each with user-facing copy and a `isRetryable` flag. No generic "Something went wrong."
- **User edits win.** Retry replaces only AI-generated logs (`userEdited == false`). The "Edited by you" tag makes the human-in-the-loop visible.
- **On-device transcription preferred** (`requiresOnDeviceRecognition`) — health speech shouldn't leave the phone just to become text.
- **Design system** (`DS` tokens + DSCard/SeverityDots/StatusBanner/Waveform) keeps styling in one place and shows component-library thinking.
- **Analytics façade** — every key event (`checkin_saved`, `ai_extraction_failed`, `log_edited`, …) goes through one logger; swapping in Amplitude/PostHog touches one file.
- **No diagnoses.** The system prompt forbids medical advice; insight copy says "line up with," never "causes."

## Edge cases handled

- Mic or speech permission denied → explicit banner with how to fix in Settings
- Recognizer unavailable/offline → fallback messaging, typing still works
- AI timeout / 5xx / garbage output → saved entry + retry button, exponential backoff
- No API key → app degrades to a plain journal
- Empty transcript → save disabled with hint
- <2 check-ins → insights show progress state, not an empty chart
- Missing HealthKit days → "—" cells, never fake zeros
- Notification permission denied → toggle reverts with explanation

## Tests

`VoiceHealthJournalTests/ExtractionTests.swift` covers JSON contract decoding
(valid, nulls, malformed) and error retryability. Run with ⌘U.

## Roadmap / talking points

- Streaming AI responses for perceived latency
- Background HealthKit observers + BGTaskScheduler for passive sync
- Keychain (then backend) for the API key
- Snapshot tests for the design system
- Correlation insights ("headaches appear on days after <6h sleep") with honest confidence framing
