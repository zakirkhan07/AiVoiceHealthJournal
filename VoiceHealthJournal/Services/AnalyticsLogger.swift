import Foundation
import os

/// Lightweight analytics façade. In production, swap the body of `log` for
/// Amplitude/PostHog/etc. — call sites never change. Events are the JD's
/// "instrument and iterate" story: every key flow emits one.
enum AnalyticsEvent: String {
    case appLaunched = "app_launched"
    case recordingStarted = "checkin_recording_started"
    case recordingStopped = "checkin_recording_stopped"
    case checkInSaved = "checkin_saved"
    case extractionSucceeded = "ai_extraction_succeeded"
    case extractionFailed = "ai_extraction_failed"
    case extractionRetried = "ai_extraction_retried"
    case logEdited = "extracted_log_edited"
    case insightsViewed = "insights_viewed"
    case doctorReportExported = "doctor_report_exported"
    case healthKitConnected = "healthkit_connected"
}

final class AnalyticsLogger {
    static let shared = AnalyticsLogger()
    private let logger = Logger(subsystem: "com.example.voicehealthjournal", category: "analytics")

    func log(_ event: AnalyticsEvent, props: [String: String] = [:]) {
        let propsString = props.map { "\($0)=\($1)" }.joined(separator: " ")
        logger.info("📊 \(event.rawValue, privacy: .public) \(propsString, privacy: .private)")
        // PRODUCTION: forward to your analytics SDK here.
    }
}
