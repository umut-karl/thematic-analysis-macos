import Foundation

struct SavedAnalysisMemo: Identifiable, Equatable {
    struct Section: Identifiable, Equatable {
        let id: Int
        let title: String?
        let markdown: String
    }

    let url: URL
    let title: String
    let createdAt: Date
    let modelID: String
    let methodProfileID: String
    let promptVersion: String
    let sections: [Section]

    var id: String { url.path }

    var methodTitle: String {
        AnalysisMethodProfile(rawValue: methodProfileID)?.title ?? methodProfileID
    }

    static func load(from url: URL, fileManager: FileManager = .default) throws -> Self {
        let markdown = try String(contentsOf: url, encoding: .utf8)
        let lines = markdown.components(separatedBy: .newlines)
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let date = (attributes?[.creationDate] as? Date)
            ?? (attributes?[.modificationDate] as? Date)
            ?? .distantPast

        let title = lines.first(where: { $0.hasPrefix("# ") })
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent

        return Self(
            url: url,
            title: title,
            createdAt: date,
            modelID: metadataValue(in: lines, keys: ["Model"]),
            methodProfileID: metadataValue(in: lines, keys: ["Yöntem profili", "Method profile"]),
            promptVersion: metadataValue(in: lines, keys: ["İstem sürümü", "Prompt version"]),
            sections: parseSections(lines)
        )
    }

    private static func metadataValue(in lines: [String], keys: [String]) -> String {
        for key in keys {
            let prefix = "- \(key):"
            guard let line = lines.first(where: { $0.hasPrefix(prefix) }) else { continue }
            return String(line.dropFirst(prefix.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " `"))
        }
        return ""
    }

    private static func parseSections(_ lines: [String]) -> [Section] {
        var sections: [Section] = []
        var currentTitle: String?
        var currentLines: [String] = []

        func isHeaderMetadata(_ line: String) -> Bool {
            line.hasPrefix("# ")
                || line.hasPrefix("> AI destekli analiz notu")
                || line.hasPrefix("> AI-assisted analysis note")
                || line.hasPrefix("- Model:")
                || line.hasPrefix("- Yöntem profili:")
                || line.hasPrefix("- Method profile:")
                || line.hasPrefix("- İstem sürümü:")
                || line.hasPrefix("- Prompt version:")
                || line.hasPrefix("- Oluşturulma:")
                || line.hasPrefix("- Created:")
        }

        func appendCurrent() {
            let body = currentLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }
            sections.append(.init(id: sections.count, title: currentTitle, markdown: body))
        }

        for line in lines where !isHeaderMetadata(line) {
            if line.hasPrefix("## ") {
                appendCurrent()
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }
        appendCurrent()
        return sections
    }
}
