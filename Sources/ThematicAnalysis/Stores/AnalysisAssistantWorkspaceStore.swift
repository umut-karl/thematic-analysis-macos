import Combine
import Foundation

@MainActor
final class AnalysisAssistantWorkspaceStore: ObservableObject {
    @Published var brief: AnalysisBrief { didSet { persist() } }
    @Published var scope: AnalysisAssistantScope { didSet { persist() } }
    @Published private(set) var persistenceError = ""

    private struct Archive: Codable {
        var brief: AnalysisBrief
        var scope: AnalysisAssistantScope
    }

    private let archiveURL: URL

    init(storageRoot: URL) {
        let directory = storageRoot.appendingPathComponent("AnalizAsistani", isDirectory: true)
        archiveURL = directory.appendingPathComponent("calisma-baglami.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: archiveURL),
           let archive = try? JSONDecoder.tematik.decode(Archive.self, from: data) {
            brief = archive.brief
            scope = archive.scope
        } else {
            brief = AnalysisBrief()
            scope = .project
        }
    }

    func normalize(for project: AnalysisProject) {
        switch scope.kind {
        case .project:
            break
        case .interview where !project.interviews.contains(where: { $0.id == scope.interviewID }):
            scope = .project
        case .theme where !project.themes.contains(where: { $0.id == scope.themeID }):
            scope = .project
        default:
            break
        }
        scope.surroundingRowCount = min(max(scope.surroundingRowCount, 0), 10)
    }

    private func persist() {
        do {
            try JSONEncoder.tematik.encode(Archive(brief: brief, scope: scope))
                .write(to: archiveURL, options: .atomic)
            persistenceError = ""
        } catch {
            persistenceError = AppLocalization.string("Analiz bağlamı kaydedilemedi: ") + error.localizedDescription
        }
    }
}
