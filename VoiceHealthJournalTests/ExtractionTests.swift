import XCTest
@testable import VoiceHealthJournal

final class ExtractionResultTests: XCTestCase {

    func testDecodesValidJSON() throws {
        let json = """
        {"summary":"You had a rough day with headaches.","moodScore":2,
         "symptoms":[{"name":"headache","severity":4,"note":"after lunch"}],
         "lifestyle":[{"category":"sleep","detail":"slept 5 hours"}]}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(ExtractionResult.self, from: json)
        XCTAssertEqual(result.symptoms.count, 1)
        XCTAssertEqual(result.symptoms[0].severity, 4)
        XCTAssertEqual(result.lifestyle[0].category, "sleep")
        XCTAssertEqual(result.moodScore, 2)
    }

    func testDecodesNullsAndEmptyArrays() throws {
        let json = """
        {"summary":"A calm day.","moodScore":null,"symptoms":[],"lifestyle":[]}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(ExtractionResult.self, from: json)
        XCTAssertNil(result.moodScore)
        XCTAssertTrue(result.symptoms.isEmpty)
    }

    func testRejectsMalformedJSON() {
        let json = "I'm sorry, here is the data: {broken".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(ExtractionResult.self, from: json))
    }
}

final class AIErrorTests: XCTestCase {
    func testRetryability() {
        XCTAssertFalse(AIError.noAPIKey.isRetryable)   // user action needed, retrying won't help
        XCTAssertTrue(AIError.timeout.isRetryable)
        XCTAssertTrue(AIError.badResponse(500).isRetryable)
        XCTAssertTrue(AIError.unparseable.isRetryable)
    }
}
