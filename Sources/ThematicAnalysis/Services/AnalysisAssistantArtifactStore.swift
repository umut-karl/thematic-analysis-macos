import Foundation

struct AnalysisAuditEntry: Codable, Equatable, Identifiable {
    enum Event: String, Codable {
        case responseGenerated = "response_generated"
        case memoSaved = "memo_saved"
    }

    let id: UUID
    let timestamp: Date
    let event: Event
    let conversationID: UUID
    let messageID: UUID
    let modelID: String
    let methodProfileID: String
    let promptVersion: String
    let evidenceScopeIDs: [String]
    let evidenceReferences: [String]
    let title: String
    let artifactPath: String?
}

enum AnalysisAssistantArtifactStore {
    private static let directoryName = "AnalizAsistani"

    static func appendAudit(
        event: AnalysisAuditEntry.Event,
        conversationID: UUID,
        messageID: UUID,
        response: AnalysisAssistantResponse,
        provenance: AnalysisRunProvenance,
        artifactPath: String? = nil,
        storageRoot: URL,
        fileManager: FileManager = .default
    ) throws {
        let directory = storageRoot.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("denetim-kaydi.json")
        var entries: [AnalysisAuditEntry] = []
        if let data = try? Data(contentsOf: url) {
            entries = (try? JSONDecoder.tematik.decode([AnalysisAuditEntry].self, from: data)) ?? []
        }
        entries.append(AnalysisAuditEntry(
            id: UUID(),
            timestamp: .now,
            event: event,
            conversationID: conversationID,
            messageID: messageID,
            modelID: provenance.modelID,
            methodProfileID: provenance.methodProfileID,
            promptVersion: provenance.promptVersion,
            evidenceScopeIDs: provenance.evidenceScopeIDs,
            evidenceReferences: response.evidenceReferences.map(\.evidenceID),
            title: response.title,
            artifactPath: artifactPath
        ))
        try JSONEncoder.tematik.encode(entries).write(to: url, options: .atomic)
    }

    static func saveMemo(
        response: AnalysisAssistantResponse,
        provenance: AnalysisRunProvenance,
        storageRoot: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = storageRoot
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("Memolar", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let stamp = filenameDateFormatter.string(from: .now)
        let base = slug(response.title).isEmpty ? "analiz-memosu" : slug(response.title)
        var url = directory.appendingPathComponent("\(stamp)-\(base).md")
        var copy = 2
        while fileManager.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(stamp)-\(base)-\(copy).md")
            copy += 1
        }

        try markdown(response: response, provenance: provenance)
            .write(to: url, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .analysisMemoSaved, object: url)
        return url
    }

    static func markdown(
        response: AnalysisAssistantResponse,
        provenance: AnalysisRunProvenance
    ) -> String {
        var lines = [
            "# \(response.title)",
            "",
            "> AI destekli analiz notu — araştırmacı tarafından gözden geçirilmeden nihai bulgu değildir.",
            "",
            "- Model: `\(provenance.modelID)`",
            "- Yöntem profili: `\(provenance.methodProfileID)`",
            "- İstem sürümü: `\(provenance.promptVersion)`",
            "- Oluşturulma: \(ISO8601DateFormatter().string(from: provenance.createdAt))",
            ""
        ]

        for block in response.blocks {
            if !block.title.isEmpty { lines += ["## \(block.title)", ""] }
            switch block.kind {
            case .paragraph:
                lines += [block.text, ""]
            case .bullets:
                lines += block.items.map { "- \($0)" }
                lines.append("")
            case .table:
                guard !block.columns.isEmpty else { continue }
                lines.append("| " + block.columns.map(escapeTableCell).joined(separator: " | ") + " |")
                lines.append("| " + block.columns.map { _ in "---" }.joined(separator: " | ") + " |")
                for row in block.rows {
                    let cells = block.columns.indices.map { index in
                        row.cells.indices.contains(index) ? escapeTableCell(row.cells[index]) : ""
                    }
                    lines.append("| " + cells.joined(separator: " | ") + " |")
                }
                lines.append("")
            case .barChart:
                lines += block.chart.map { "- \($0.label): \($0.value.formatted())" }
                lines.append("")
            }
        }

        if !response.evidenceReferences.isEmpty {
            lines += ["## Kanıt bağlantıları", ""]
            lines += response.evidenceReferences.map { "- `\($0.evidenceID)` — \($0.claim)" }
            lines.append("")
        }
        if !response.followUpQuestions.isEmpty {
            lines += ["## Takip soruları", ""]
            lines += response.followUpQuestions.map { "- \($0)" }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func escapeTableCell(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func slug(_ value: String) -> String {
        let joined = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .split(separator: "-")
            .joined(separator: "-")
        return String(joined.prefix(64))
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
