import Foundation
import XCTest
@testable import ThematicAnalysis

final class ProjectLibraryStoreTests: XCTestCase {
    @MainActor
    func testLegacyProjectIsCopiedIntoLibraryOnlyOnce() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let segment = TranscriptSegment(order: 1, speaker: "A", start: "00:00", end: "00:03", text: "Korunacak veri")
        let legacy = AnalysisProject(
            name: "Existing Study",
            interviews: [Interview(name: "Interview", participant: "Participant A", segments: [segment])],
            themes: [],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let legacyURL = root.appendingPathComponent("active-project.json")
        try JSONEncoder.thematic.encode(legacy).write(to: legacyURL, options: .atomic)

        let firstLaunch = ProjectLibraryStore(storageRoot: root)
        XCTAssertEqual(firstLaunch.projects.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        let item = try XCTUnwrap(firstLaunch.projects.first)
        firstLaunch.openProject(item)
        XCTAssertEqual(firstLaunch.activeProjectStore?.project.interviews.first?.segments.first?.text, "Korunacak veri")
        firstLaunch.closeProject()

        let secondLaunch = ProjectLibraryStore(storageRoot: root)
        XCTAssertEqual(secondLaunch.projects.count, 1)
    }

    @MainActor
    func testCreatesAndReopensIndependentProjects() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProjectLibraryStore(storageRoot: root)

        XCTAssertTrue(library.createProject(named: "First Study"))
        XCTAssertEqual(library.activeProjectStore?.project.name, "First Study")
        XCTAssertEqual(library.activeProjectStore?.project.interviews.count, 0)
        XCTAssertEqual(library.activeProjectStore?.project.themes.count, 0)
        library.closeProject()

        XCTAssertTrue(library.createProject(named: "Second Study"))
        library.closeProject()
        XCTAssertEqual(Set(library.projects.map(\.name)), ["First Study", "Second Study"])

        let first = try XCTUnwrap(library.projects.first(where: { $0.name == "First Study" }))
        library.openProject(first)
        XCTAssertEqual(library.activeProjectStore?.project.name, "First Study")
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ThematicAnalysis-Library-Tests-\(UUID().uuidString)")
    }
}
