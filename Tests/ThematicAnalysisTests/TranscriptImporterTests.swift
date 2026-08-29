import XCTest
@testable import ThematicAnalysis

final class TranscriptImporterTests: XCTestCase {
    func testMapsEnglishTranscriptHeaders() {
        let rows = [
            ["order", "part", "speaker", "start", "end", "text"],
            ["1", "2", "A", "00:01", "00:04", " First excerpt "],
            ["2", "2", "B", "00:05", "00:08", "Second excerpt"]
        ]
        let segments = TranscriptImporter.makeSegments(rows)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].order, 1)
        XCTAssertEqual(segments[0].part, 2)
        XCTAssertEqual(segments[0].speaker, "A")
        XCTAssertEqual(segments[0].text, "First excerpt")
    }

    func testSkipsEmptyTextRows() {
        let rows = [["order", "text"], ["1", ""], ["2", "One excerpt"]]
        XCTAssertEqual(TranscriptImporter.makeSegments(rows).map(\.order), [2])
    }

    func testOptionalXLSXFixture() throws {
        guard let path = ProcessInfo.processInfo.environment["THEMATIC_ANALYSIS_FIXTURE"] else {
            throw XCTSkip("No local XLSX fixture path was provided")
        }
        let segments = try TranscriptImporter.importFile(at: URL(fileURLWithPath: path))
        XCTAssertEqual(segments.count, 480)
        XCTAssertEqual(segments.first?.speaker, "A")
        XCTAssertFalse(segments.last?.text.isEmpty ?? true)
    }

    func testParsesNestedThemeMarkdown() {
        let markdown = """
        # Themes
        ## **Experiences**
        ### Interaction
        - Emotional outcomes
        \t- Distrust
        \t\t- Source uncertainty
        ## **Attitudes and beliefs**
        """
        let nodes = ThemeMarkdownImporter.parse(markdown)
        XCTAssertEqual(nodes.count, 6)
        XCTAssertNil(nodes[0].parentID)
        XCTAssertEqual(nodes[1].parentID, nodes[0].id)
        XCTAssertEqual(nodes[4].parentID, nodes[3].id)
        XCTAssertNil(nodes[5].parentID)
    }

    func testOptionalThemeFixture() throws {
        guard let path = ProcessInfo.processInfo.environment["THEMATIC_ANALYSIS_THEME_FIXTURE"] else {
            throw XCTSkip("No local Markdown fixture path was provided")
        }
        let markdown = try String(contentsOfFile: path, encoding: .utf8)
        let nodes = ThemeMarkdownImporter.parse(markdown)
        XCTAssertGreaterThan(nodes.count, 180)
        XCTAssertEqual(nodes.filter { $0.parentID == nil }.count, 4)
    }

    func testLegacyInterviewWithoutDemographicsStillDecodes() throws {
        let interview = Interview(
            name: "Participant A Transcript",
            participant: "Participant A",
            participantDetails: ParticipantDetails(gender: "Woman"),
            segments: []
        )
        let encoded = try JSONEncoder.thematic.encode(interview)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "participantDetails")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder.thematic.decode(Interview.self, from: legacyData)
        XCTAssertEqual(decoded.participant, "Participant A")
        XCTAssertNil(decoded.participantDetails)
    }

    func testLegacyParticipantDetailsGainNewOptionalFields() throws {
        let legacy = Data(#"{"gender":"Woman","age":"35","education":"Bachelor's degree","occupation":"Researcher","location":"Ankara","notes":""}"#.utf8)
        let details = try JSONDecoder().decode(ParticipantDetails.self, from: legacy)

        XCTAssertEqual(details.occupation, "Researcher")
        XCTAssertEqual(details.location, "Ankara")
        XCTAssertEqual(details.employmentStatus, "")
        XCTAssertEqual(details.sector, "")
        XCTAssertEqual(details.experienceYears, "")
        XCTAssertEqual(details.maritalStatus, "")
    }

    @MainActor
    func testCreatesParticipantFromOptionalXLSXFixture() async throws {
        guard let path = ProcessInfo.processInfo.environment["THEMATIC_ANALYSIS_FIXTURE"] else {
            throw XCTSkip("No local XLSX fixture path was provided")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ThematicAnalysis-Test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AnalysisStore(storageRoot: root)
        let before = store.project.interviews.count
        let details = ParticipantDetails(gender: "Woman", age: "35", occupation: "Researcher")
        let result = await store.createParticipant(name: "Participant B", details: details, transcriptURL: URL(fileURLWithPath: path))
        XCTAssertTrue(result)
        XCTAssertEqual(store.project.interviews.count, before + 1)
        XCTAssertEqual(store.selectedInterview?.name, "Participant B Transcript")
        XCTAssertEqual(store.selectedInterview?.segments.count, 480)
        XCTAssertEqual(store.selectedInterview?.participantDetails?.occupation, "Researcher")
    }
}
