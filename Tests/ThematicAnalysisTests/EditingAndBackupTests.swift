import Foundation
import XCTest
@testable import ThematicAnalysis

final class EditingAndBackupTests: XCTestCase {
    @MainActor
    func testParticipantInformationCanBeUpdatedWithoutChangingTranscriptOrCoding() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AnalysisStore(storageRoot: root, initialProject: Self.fixtureProject())
        let interview = try XCTUnwrap(store.project.interviews.first)
        let segmentIDs = interview.segments.map(\.id)
        let codingUnitIDs = interview.codingUnits.map(\.id)
        var details = ParticipantDetails()
        details.gender = "Woman"
        details.age = "38"
        details.education = "Doctorate"
        details.occupation = "Researcher"
        details.location = "Ankara"
        details.notes = "A follow-up interview was scheduled."

        XCTAssertTrue(store.updateParticipant(
            interviewID: interview.id,
            participantName: "K-07",
            interviewName: "Second Interview",
            details: details
        ))

        let updated = try XCTUnwrap(store.project.interviews.first(where: { $0.id == interview.id }))
        XCTAssertEqual(updated.participant, "K-07")
        XCTAssertEqual(updated.name, "Second Interview")
        XCTAssertEqual(updated.participantDetails, details)
        XCTAssertEqual(updated.segments.map(\.id), segmentIDs)
        XCTAssertEqual(updated.codingUnits.map(\.id), codingUnitIDs)
    }

    @MainActor
    func testThemeNarrativePersistsWithProject() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ThematicAnalysis-Theme-Note-Test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AnalysisStore(storageRoot: root, initialProject: Self.fixtureProject())
        let themeID = try XCTUnwrap(store.project.themes.first?.id)

        store.updateThemeNote(themeID, note: "This theme covers how the participant defines artificial intelligence.")
        store.persist()

        let restored = AnalysisStore(storageRoot: root)
        XCTAssertEqual(restored.themeNote(themeID), "This theme covers how the participant defines artificial intelligence.")
    }

    @MainActor
    func testMergingRowsPreservesTextAndRenumbersTranscript() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AnalysisStore(storageRoot: root, initialProject: Self.fixtureProject())
        let before = try XCTUnwrap(store.selectedInterview?.segments)
        store.selectedSegmentIDs = Set(before.prefix(2).map(\.id))
        store.mergeSelectedTranscriptRows()
        let after = try XCTUnwrap(store.selectedInterview?.segments)
        XCTAssertEqual(after.count, before.count - 1)
        XCTAssertTrue(after[0].text.contains(before[0].text))
        XCTAssertTrue(after[0].text.contains(before[1].text))
        XCTAssertEqual(after.map(\.order), Array(1...after.count))
    }

    @MainActor
    func testDeletingRowRemovesItFromTranscript() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AnalysisStore(storageRoot: root, initialProject: Self.fixtureProject())
        let before = try XCTUnwrap(store.selectedInterview?.segments)
        store.selectedSegmentIDs = [try XCTUnwrap(before.first?.id)]
        store.deleteSelectedTranscriptRows()
        XCTAssertEqual(store.selectedInterview?.segments.count, before.count - 1)
    }

    @MainActor
    func testReadsRestorableZipProjectArchive() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AnalysisStore(storageRoot: root.appendingPathComponent("store"))
        let bundle = root.appendingPathComponent("Backup", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try JSONEncoder.thematic.encode(store.project).write(to: bundle.appendingPathComponent("Project-Data.json"))
        let archive = root.appendingPathComponent("project.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", bundle.path, archive.path]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let restored = try ExportService.readProject(at: archive)
        XCTAssertEqual(restored.name, store.project.name)
        XCTAssertEqual(restored.interviews.count, store.project.interviews.count)
    }

    @MainActor
    func testAddingAnotherThemeSavesIntoSameCodingUnitAndKeepsSelection() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AnalysisStore(storageRoot: root, initialProject: Self.fixtureProject())
        let segmentID = try XCTUnwrap(store.selectedInterview?.segments.first?.id)
        let themes = store.project.themes.prefix(2).map(\.id)
        XCTAssertEqual(themes.count, 2)
        store.selectedSegmentIDs = [segmentID]

        _ = store.saveCodingSelection(themeIDs: [themes[0]], memo: "Initial memo", keepSelection: true)
        _ = store.saveCodingSelection(themeIDs: [themes[1]], memo: "", keepSelection: true)

        XCTAssertEqual(store.selectedSegmentIDs, [segmentID])
        let matching = store.selectedInterview?.codingUnits.filter { Set($0.segmentIDs) == [segmentID] }
        XCTAssertEqual(matching?.count, 1)
        XCTAssertEqual(matching?.first?.themeIDs, Set(themes))
    }

    @MainActor
    func testFreshStoreStartsWithoutStarterData() {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AnalysisStore(storageRoot: root)
        XCTAssertTrue(store.project.interviews.isEmpty)
        XCTAssertTrue(store.project.themes.isEmpty)
    }

    private static func fixtureProject() -> AnalysisProject {
        let firstTheme = ThemeNode(name: "Theme A", parentID: nil, colorIndex: 0)
        let secondTheme = ThemeNode(name: "Theme B", parentID: nil, colorIndex: 1)
        let segments = [
            TranscriptSegment(order: 1, speaker: "A", start: "00:00", end: "00:03", text: "First excerpt."),
            TranscriptSegment(order: 2, speaker: "B", start: "00:03", end: "00:06", text: "Second excerpt."),
            TranscriptSegment(order: 3, speaker: "A", start: "00:06", end: "00:09", text: "Third excerpt.")
        ]
        return AnalysisProject(
            name: "Test Project",
            interviews: [Interview(name: "Test Interview", participant: "Participant A", segments: segments)],
            themes: [firstTheme, secondTheme]
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ThematicAnalysis-Tests-\(UUID().uuidString)")
    }
}
