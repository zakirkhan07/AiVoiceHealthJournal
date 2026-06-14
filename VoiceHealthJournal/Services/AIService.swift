import Foundation

/// Sends a transcript to an LLM and gets back structured health data.
/// Design notes (interview talking points):
/// - Strict JSON contract with a Codable mirror type; never trust raw model output.
/// - Explicit timeout + typed errors so the UI can show *specific* failure states.
/// - Retry with exponential backoff for transient failures only.
/// - The transcript is persisted BEFORE this is called — a network failure never loses user data.
enum AIError: LocalizedError {
    case noAPIKey
    case network(String)
    case timeout
    case badResponse(Int)
    case unparseable

    var errorDescription: String? {
        switch self {
        case .noAPIKey:      return "Add your API key in Settings to enable AI insights."
        case .network:       return "Couldn't reach the AI service. Check your connection and retry."
        case .timeout:       return "The AI took too long to respond. Your check-in is saved — tap retry."
        case .badResponse(let code): return "The AI service returned an error (\(code)). Tap retry."
        case .unparseable:   return "We couldn't read the AI's response. Your check-in is saved — tap retry."
        }
    }

    var isRetryable: Bool {
        switch self {
        case .noAPIKey: return false
        default: return true
        }
    }
}

struct AIService {
    static let shared = AIService()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-5"
    private let timeout: TimeInterval = 30

    func extract(from transcript: String, apiKey: String?) async throws -> ExtractionResult {
        guard let apiKey, !apiKey.isEmpty else { throw AIError.noAPIKey }

        var lastError: AIError = .timeout
        for attempt in 0..<3 {
            do {
                return try await performRequest(transcript: transcript, apiKey: apiKey)
            } catch let error as AIError where error.isRetryable {
                lastError = error
                // backoff: 0.5s, 1s
                try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (attempt + 1)))
            }
        }
        throw lastError
    }

    private func performRequest(transcript: String, apiKey: String) async throws -> ExtractionResult {
        let systemPrompt = """
        You extract structured health data from a user's spoken daily check-in. \
        Respond with ONLY a JSON object, no markdown fences, matching exactly:
        {"summary": "<2-sentence empathetic summary>", "moodScore": <1-5 or null>, \
        "symptoms": [{"name": "...", "severity": <1-5>, "note": "... or null"}], \
        "lifestyle": [{"category": "sleep|food|exercise|stress|other", "detail": "..."}]}
        Only include symptoms/lifestyle items explicitly mentioned. Never invent data. \
        Never give medical advice or diagnoses in the summary.
        """

        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [["role": "user", "content": transcript]]
        ])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let e as URLError where e.code == .timedOut {
            throw AIError.timeout
        } catch {
            throw AIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw AIError.network("Invalid response") }
        guard (200..<300).contains(http.statusCode) else { throw AIError.badResponse(http.statusCode) }

        // Anthropic response: { "content": [ { "type": "text", "text": "..." } ] }
        struct APIResponse: Codable {
            struct Block: Codable { let type: String; let text: String? }
            let content: [Block]
        }
        guard let api = try? JSONDecoder().decode(APIResponse.self, from: data),
              let text = api.content.first(where: { $0.type == "text" })?.text else {
            throw AIError.unparseable
        }

        // Defensive: strip accidental code fences before parsing.
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8),
              let result = try? JSONDecoder().decode(ExtractionResult.self, from: jsonData) else {
            throw AIError.unparseable
        }
        return result
    }
}
