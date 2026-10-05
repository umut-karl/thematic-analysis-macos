import Combine
import Foundation

extension Notification.Name {
    static let analysisMemoSaved = Notification.Name("ThematicAnalysis.analysisMemoSaved")
}

@MainActor
final class SavedAnalysisMemoStore: ObservableObject {
    @Published private(set) var memos: [SavedAnalysisMemo] = []
    @Published var selectedMemoID: String?
    @Published private(set) var errorMessage = ""

    private let directory: URL
    private let fileManager: FileManager

    init(storageRoot: URL, fileManager: FileManager = .default) {
        directory = storageRoot
            .appendingPathComponent("AnalizAsistani", isDirectory: true)
            .appendingPathComponent("Memolar", isDirectory: true)
        self.fileManager = fileManager
        reload()
    }

    var selectedMemo: SavedAnalysisMemo? {
        guard let selectedMemoID else { return nil }
        return memos.first { $0.id == selectedMemoID }
    }

    func reload() {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let urls = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            memos = urls
                .filter { $0.pathExtension.lowercased() == "md" }
                .compactMap { try? SavedAnalysisMemo.load(from: $0, fileManager: fileManager) }
                .sorted { left, right in
                    if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
                    return left.title.localizedStandardCompare(right.title) == .orderedAscending
                }
            if let selectedMemoID, memos.contains(where: { $0.id == selectedMemoID }) {
                self.selectedMemoID = selectedMemoID
            } else {
                selectedMemoID = memos.first?.id
            }
            errorMessage = ""
        } catch {
            memos = []
            selectedMemoID = nil
            errorMessage = AppLocalization.string("Kaydedilen analizler yüklenemedi: ") + error.localizedDescription
        }
    }
}
