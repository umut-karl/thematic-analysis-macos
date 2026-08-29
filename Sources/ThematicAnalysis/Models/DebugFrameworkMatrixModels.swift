import Foundation
import Observation

enum FrameworkColumnSource: Hashable {
    case candidateTheme(String)
    case code(String)
    case custom
}

struct FrameworkMatrixColumn: Identifiable, Hashable {
    let id: String
    var title: String
    let source: FrameworkColumnSource
    let colorIndex: Int
    var summaries: [String: String]

    var kindLabel: String {
        switch source {
        case .candidateTheme: "Theme"
        case .code: "Kod"
        case .custom: "Custom"
        }
    }

    var isCustom: Bool {
        if case .custom = source { return true }
        return false
    }
}

@Observable
final class DebugFrameworkMatrixWorkspace {
    var columns: [FrameworkMatrixColumn]
    var visibleColumnIDs: Set<String>
    var summaryLinkIDs: [String: Set<String>]

    init(dataset: DebugResearchDataset) {
        let themeColumns = dataset.candidateThemes.map { theme in
            FrameworkMatrixColumn(
                id: theme.id,
                title: theme.title,
                source: .candidateTheme(theme.id),
                colorIndex: theme.colorIndex,
                summaries: theme.frameworkSummaries
            )
        }
        let codeColumns = dataset.codebook.map { code in
            FrameworkMatrixColumn(
                id: "code:\(code.id)",
                title: code.name,
                source: .code(code.id),
                colorIndex: code.colorIndex,
                summaries: [:]
            )
        }

        columns = themeColumns + codeColumns
        visibleColumnIDs = Set(themeColumns.map(\.id))

        var initialLinks: [String: Set<String>] = [:]
        for theme in dataset.candidateThemes {
            for participant in dataset.participants {
                let evidenceIDs = Set(dataset.excerpts(for: theme, participantID: participant.id).map(\.id))
                initialLinks[Self.cellKey(participantID: participant.id, columnID: theme.id)] = evidenceIDs
            }
        }
        summaryLinkIDs = initialLinks
    }

    @discardableResult
    func addCustomColumn(named name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !columns.contains(where: { $0.title.compare(trimmed, options: .caseInsensitive) == .orderedSame }) else {
            return nil
        }

        let id = "custom:\(UUID().uuidString)"
        let colorIndex = columns.count % 6
        columns.append(
            FrameworkMatrixColumn(
                id: id,
                title: trimmed,
                source: .custom,
                colorIndex: colorIndex,
                summaries: [:]
            )
        )
        visibleColumnIDs.insert(id)
        return id
    }

    func deleteCustomColumn(_ id: String) {
        guard columns.first(where: { $0.id == id })?.isCustom == true else { return }
        columns.removeAll { $0.id == id }
        visibleColumnIDs.remove(id)
        summaryLinkIDs = summaryLinkIDs.filter { !$0.key.hasSuffix("|\(id)") }
    }

    func linkedExcerptIDs(participantID: String, columnID: String) -> Set<String> {
        summaryLinkIDs[Self.cellKey(participantID: participantID, columnID: columnID)] ?? []
    }

    func setLinkedExcerptIDs(_ ids: Set<String>, participantID: String, columnID: String) {
        summaryLinkIDs[Self.cellKey(participantID: participantID, columnID: columnID)] = ids
    }

    private static func cellKey(participantID: String, columnID: String) -> String {
        "\(participantID)|\(columnID)"
    }
}
