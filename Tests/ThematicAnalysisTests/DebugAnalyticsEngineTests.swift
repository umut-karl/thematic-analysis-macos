import XCTest
@testable import ThematicAnalysis

final class DebugAnalyticsEngineTests: XCTestCase {
    func testProjectAnalyticsRollsDescendantAssignmentsIntoComparedTheme() throws {
        let root = ThemeNode(name: "Tool", parentID: nil, colorIndex: 0)
        let child = ThemeNode(name: "Assistant", parentID: root.id, colorIndex: 0)
        let other = ThemeNode(name: "Tehdit", parentID: nil, colorIndex: 1)
        let firstSegment = TranscriptSegment(order: 1, part: nil, speaker: "A", start: "", end: "", text: "Birinci")
        let secondSegment = TranscriptSegment(order: 1, part: nil, speaker: "B", start: "", end: "", text: "Second")
        let first = Interview(
            name: "Participant A Transcript",
            participant: "Participant A",
            participantDetails: nil,
            segments: [firstSegment],
            codingUnits: [
                CodingUnit(segmentIDs: [firstSegment.id], themeIDs: [child.id], memo: ""),
                CodingUnit(segmentIDs: [firstSegment.id], themeIDs: [root.id], memo: "")
            ]
        )
        let second = Interview(
            name: "Participant B Transcript",
            participant: "Participant B",
            participantDetails: nil,
            segments: [secondSegment],
            codingUnits: [CodingUnit(segmentIDs: [secondSegment.id], themeIDs: [other.id], memo: "")]
        )
        let project = AnalysisProject(name: "Test", interviews: [first, second], themes: [root, child, other])

        let dataset = DebugAnalyticsEngine.project(project, focusThemeID: nil, themeLimit: 5)
        let rootMetric = try XCTUnwrap(dataset.metrics.first(where: { $0.theme.name == "Tool" }))
        let otherMetric = try XCTUnwrap(dataset.metrics.first(where: { $0.theme.name == "Tehdit" }))

        XCTAssertEqual(rootMetric.occurrenceCount, 2)
        XCTAssertEqual(rootMetric.participantCount, 1)
        XCTAssertEqual(rootMetric.prevalence, 0.5, accuracy: 0.001)
        XCTAssertEqual(rootMetric.occurrenceShare, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(otherMetric.occurrenceCount, 1)
        XCTAssertEqual(dataset.matrixScore(participantID: first.id.uuidString, themeID: root.id.uuidString, strongThreshold: 2), 2)
        XCTAssertEqual(dataset.matrixScore(participantID: first.id.uuidString, themeID: root.id.uuidString, strongThreshold: 3), 1)
    }

    func testFocusedAnalyticsComparesImmediateChildren() throws {
        let root = ThemeNode(name: "Ontoloji", parentID: nil, colorIndex: 0)
        let child = ThemeNode(name: "Tool", parentID: root.id, colorIndex: 0)
        let segment = TranscriptSegment(order: 1, part: nil, speaker: "A", start: "", end: "", text: "Text")
        let interview = Interview(
            name: "Interview",
            participant: "Participant A",
            participantDetails: nil,
            segments: [segment],
            codingUnits: [CodingUnit(segmentIDs: [segment.id], themeIDs: [child.id], memo: "")]
        )
        let project = AnalysisProject(name: "Test", interviews: [interview], themes: [root, child])

        let dataset = DebugAnalyticsEngine.project(project, focusThemeID: root.id, themeLimit: 5)

        XCTAssertEqual(dataset.themes.map(\.name), ["Tool"])
        XCTAssertEqual(dataset.totalOccurrences, 1)
    }
}
