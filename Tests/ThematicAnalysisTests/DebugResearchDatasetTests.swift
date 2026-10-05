import XCTest
@testable import ThematicAnalysis

final class DebugResearchDatasetTests: XCTestCase {
    private let dataset = DebugResearchDemoData.demo

    func testAndQueryReturnsOnlyExcerptsContainingBothCodes() {
        let results = dataset.query(
            firstCodeID: "blackbox",
            secondCodeID: "threat",
            operator: .and,
            usageGroup: nil
        )

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.codeIDs.contains("blackbox") && $0.codeIDs.contains("threat") })
    }

    func testQueryCanBeScopedToParticipantGroup() {
        let results = dataset.query(
            firstCodeID: "helper",
            secondCodeID: "partner",
            operator: .or,
            usageGroup: "Yeni kullanıcı"
        )

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { dataset.participant($0.participantID)?.usageGroup == "Yeni kullanıcı" })
    }

    func testFrameworkThemeLinksSummariesAndEvidenceToSameParticipant() throws {
        let theme = try XCTUnwrap(dataset.candidateThemes.first { $0.id == "trust-opacity" })
        let participant = try XCTUnwrap(dataset.participant("p1"))
        let evidence = dataset.excerpts(for: theme, participantID: participant.id)

        XCTAssertNotNil(theme.frameworkSummaries[participant.id])
        XCTAssertFalse(evidence.isEmpty)
        XCTAssertTrue(evidence.allSatisfy { $0.participantID == participant.id })
    }

    func testFrameworkWorkspaceOffersThemeAndCodeColumns() {
        let workspace = DebugFrameworkMatrixWorkspace(dataset: dataset)

        XCTAssertEqual(
            workspace.columns.count,
            dataset.candidateThemes.count + dataset.codebook.count
        )
        XCTAssertEqual(
            workspace.visibleColumnIDs,
            Set(dataset.candidateThemes.map(\.id))
        )
    }

    func testFrameworkWorkspaceCanAddEditAndDeleteCustomColumn() throws {
        let workspace = DebugFrameworkMatrixWorkspace(dataset: dataset)
        let id = try XCTUnwrap(workspace.addCustomColumn(named: "Yeni karşılaştırma"))
        let index = try XCTUnwrap(workspace.columns.firstIndex(where: { $0.id == id }))

        XCTAssertTrue(workspace.visibleColumnIDs.contains(id))
        workspace.columns[index].summaries["p0"] = "Ayşe için düzenlenmiş özet"
        XCTAssertEqual(workspace.columns[index].summaries["p0"], "Ayşe için düzenlenmiş özet")

        workspace.deleteCustomColumn(id)
        XCTAssertFalse(workspace.columns.contains(where: { $0.id == id }))
        XCTAssertFalse(workspace.visibleColumnIDs.contains(id))
    }

    func testFrameworkWorkspaceKeepsSummaryLinksSeparateFromCellEvidence() throws {
        let workspace = DebugFrameworkMatrixWorkspace(dataset: dataset)
        let initial = workspace.linkedExcerptIDs(participantID: "p4", columnID: "controlled-partnership")

        XCTAssertEqual(initial, Set(["e09", "e10"]))

        workspace.setLinkedExcerptIDs(["e09"], participantID: "p4", columnID: "controlled-partnership")
        XCTAssertEqual(
            workspace.linkedExcerptIDs(participantID: "p4", columnID: "controlled-partnership"),
            Set(["e09"])
        )
    }

    func testProjectFrameworkDatasetUsesProjectParticipantsThemesAndCodingEvidence() throws {
        let rootTheme = ThemeNode(name: "Deneyimler", parentID: nil, colorIndex: 1)
        let childTheme = ThemeNode(name: "İş birliği", parentID: rootTheme.id, colorIndex: 1)
        let segment = TranscriptSegment(order: 1, speaker: "A", start: "00:01", end: "00:05", text: "Birlikte çalışmak daha hızlıydı.")
        let coding = CodingUnit(segmentIDs: [segment.id], themeIDs: [childTheme.id], memo: "Ortak çalışma")
        let interview = Interview(
            name: "Ayşe Görüşmesi",
            participant: "Ayşe",
            participantDetails: ParticipantDetails(gender: "Kadın", occupation: "Araştırmacı"),
            segments: [segment],
            codingUnits: [coding]
        )
        let project = AnalysisProject(name: "Proje", interviews: [interview], themes: [rootTheme, childTheme])

        let result = ProjectResearchDatasetBuilder.build(project)
        let frameworkTheme = try XCTUnwrap(result.candidateThemes.first)

        XCTAssertEqual(result.participants.map(\.name), ["Ayşe"])
        XCTAssertEqual(frameworkTheme.title, "Deneyimler")
        XCTAssertEqual(result.excerpts(for: frameworkTheme).map(\.text), [segment.text])
        XCTAssertEqual(result.excerpts.first?.analyticMemo, "Ortak çalışma")
    }
}
