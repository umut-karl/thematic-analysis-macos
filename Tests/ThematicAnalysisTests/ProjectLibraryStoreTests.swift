import Foundation
import XCTest
@testable import ThematicAnalysis

final class ProjectLibraryStoreTests: XCTestCase {
    @MainActor
    func testLegacyProjectIsCopiedIntoLibraryOnlyOnce() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let segment = TranscriptSegment(order: 1, speaker: "A", start: "00:00", end: "00:03", text: "Data to preserve")
        let legacy = AnalysisProject(
            name: "Existing Study",
            interviews: [Interview(name: "Interview", participant: "Participant A", segments: [segment])],
            themes: [],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let legacyURL = root.appendingPathComponent("active-project.json")
        try JSONEncoder.thematic.encode(legacy).write(to: legacyURL, options: .atomic)

        let firstLaunch = ProjectLibraryStore(storageRoot: root, includeDemoProject: false)
        XCTAssertEqual(firstLaunch.projects.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        let item = try XCTUnwrap(firstLaunch.projects.first)
        firstLaunch.openProject(item)
        XCTAssertEqual(firstLaunch.activeProjectStore?.project.interviews.first?.segments.first?.text, "Data to preserve")
        firstLaunch.closeProject()

        let secondLaunch = ProjectLibraryStore(storageRoot: root, includeDemoProject: false)
        XCTAssertEqual(secondLaunch.projects.count, 1)
    }

    @MainActor
    func testCreatesAndReopensIndependentProjects() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProjectLibraryStore(storageRoot: root, includeDemoProject: false)

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

    @MainActor
    func testInstallsEditableSyntheticDemoWithoutChangingBlankProjectDefaults() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProjectLibraryStore(storageRoot: root)

        let demo = try XCTUnwrap(library.projects.first(where: { $0.isDemo == true }))
        library.openProject(demo)
        let project = try XCTUnwrap(library.activeProjectStore?.project)
        XCTAssertEqual(project.name, "Demo — AI-Assisted Work")
        XCTAssertEqual(project.interviews.count, 1)
        XCTAssertEqual(project.interviews[0].segments.count, 8)
        XCTAssertEqual(project.interviews[0].codingUnits.count, 5)
        XCTAssertEqual(project.themes.count, 11)
        XCTAssertTrue(project.themes.contains { theme in
            guard let parentID = theme.parentID,
                  let parent = project.themes.first(where: { $0.id == parentID }),
                  let grandparentID = parent.parentID else { return false }
            return project.themes.contains(where: { $0.id == grandparentID })
        })

        library.closeProject()
        XCTAssertTrue(library.createProject(named: "Blank Study"))
        XCTAssertTrue(library.activeProjectStore?.project.themes.isEmpty == true)
        XCTAssertTrue(library.activeProjectStore?.project.interviews.isEmpty == true)
        library.closeProject()

        let reopenedLibrary = ProjectLibraryStore(storageRoot: root)
        XCTAssertEqual(reopenedLibrary.projects.filter { $0.isDemo == true }.count, 1)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ThematicAnalysis-Library-Tests-\(UUID().uuidString)")
    }
}
