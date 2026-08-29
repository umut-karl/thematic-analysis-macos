import Foundation
import XCTest
@testable import ThematicAnalysis

final class OpenAITranscriptionTests: XCTestCase {
    func testSegmenterPreservesParagraphsAsEditableRows() {
        let segments = TranscriptionSegmenter.segments(from: "First paragraph.\n\nSecond paragraph.")
        XCTAssertEqual(segments.map(\.text), ["First paragraph.", "Second paragraph."])
        XCTAssertEqual(segments.map(\.order), [1, 2])
        XCTAssertEqual(segments.map(\.speaker), ["—", "—"])
    }

    func testSegmenterBreaksSingleLongTranscriptAtSentenceBoundaries() {
        let transcript = "First sentence. The second sentence is longer. Third sentence."
        let segments = TranscriptionSegmenter.segments(from: transcript, targetCharacterCount: 30)
        XCTAssertGreaterThan(segments.count, 1)
        XCTAssertEqual(segments.map(\.text).joined(separator: " "), transcript)
    }

    func testMultipartBodyIncludesModelAndAudioFile() throws {
        var body = MultipartFormData(boundary: "TEST-BOUNDARY")
        body.appendField(name: "model", value: "gpt-4o-transcribe-diarize")
        body.appendField(name: "response_format", value: "diarized_json")
        body.appendField(name: "chunking_strategy", value: "auto")
        body.appendFile(name: "file", filename: "interview.m4a", mimeType: "audio/mp4", data: Data([0x01, 0x02]))
        let text = try XCTUnwrap(String(data: body.finalized(), encoding: .utf8))
        XCTAssertTrue(text.contains("name=\"model\""))
        XCTAssertTrue(text.contains("gpt-4o-transcribe-diarize"))
        XCTAssertTrue(text.contains("diarized_json"))
        XCTAssertTrue(text.contains("chunking_strategy"))
        XCTAssertTrue(text.contains("filename=\"interview.m4a\""))
        XCTAssertTrue(text.hasSuffix("--TEST-BOUNDARY--\r\n"))
    }

    func testDecodesDiarizedJSONSegments() throws {
        let data = Data("""
        {"segments":[
          {"speaker":"A","start":0.25,"end":3.8,"text":"Hello."},
          {"speaker":"B","start":3.8,"end":8.1,"text":"Thank you."}
        ]}
        """.utf8)
        let segments = try OpenAITranscriptionService.decodeDiarizedResponse(data)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].speaker, "A")
        XCTAssertEqual(segments[1].start, 3.8)
    }

    @MainActor
    func testCreatesNewCaseFromTranscription() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ThematicAnalysis-Transcribe-Test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AnalysisStore(storageRoot: root)
        let before = store.project.interviews.count

        let interviewID = store.createTranscribedCase(
            participantName: "Participant B",
            interviewName: "Participant B GPT Interview",
            transcript: "First excerpt.\nSecond excerpt.",
            sourceFileName: "participant-b.m4a",
            model: "gpt-transcribe"
        )

        XCTAssertNotNil(interviewID)
        XCTAssertEqual(store.project.interviews.count, before + 1)
        XCTAssertEqual(store.selectedInterview?.participant, "Participant B")
        XCTAssertEqual(store.selectedInterview?.name, "Participant B GPT Interview")
        XCTAssertEqual(store.selectedInterview?.segments.count, 2)
        XCTAssertTrue(store.selectedInterview?.participantDetails?.notes.contains("gpt-transcribe") == true)
    }

    @MainActor
    func testCreatesDiarizedCaseWithMappedSpeakersAndTimes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ThematicAnalysis-Diarize-Test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AnalysisStore(storageRoot: root)
        let source = [
            OpenAITranscriptionSegment(speaker: "A", start: 0.2, end: 4.1, text: "Welcome."),
            OpenAITranscriptionSegment(speaker: "B", start: 4.2, end: 65.3, text: "Thank you.")
        ]
        var details = ParticipantDetails()
        details.age = "32"
        details.occupation = "Researcher"
        details.notes = "Pre-interview note"

        let interviewID = store.createDiarizedCase(
            participantName: "Participant A",
            interviewName: "Participant A Diarized Interview",
            participantDetails: details,
            diarizedSegments: source,
            speakerNames: ["A": "Interviewer", "B": "Participant A"],
            sourceFileName: "participant-a.m4a",
            model: "gpt-4o-transcribe-diarize"
        )

        XCTAssertNotNil(interviewID)
        XCTAssertEqual(store.selectedInterview?.segments.map(\.speaker), ["Interviewer", "Participant A"])
        XCTAssertEqual(store.selectedInterview?.segments.map(\.start), ["00:00", "00:04"])
        XCTAssertEqual(store.selectedInterview?.segments.map(\.end), ["00:05", "01:06"])
        XCTAssertEqual(store.selectedInterview?.participantDetails?.age, "32")
        XCTAssertEqual(store.selectedInterview?.participantDetails?.occupation, "Researcher")
        XCTAssertTrue(store.selectedInterview?.participantDetails?.notes.contains("Pre-interview note") == true)
        XCTAssertTrue(store.selectedInterview?.participantDetails?.notes.contains("gpt-4o-transcribe-diarize") == true)
    }
}
