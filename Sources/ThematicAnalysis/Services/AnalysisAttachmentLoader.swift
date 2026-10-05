import Foundation
import UniformTypeIdentifiers

enum AnalysisAttachmentError: LocalizedError, Equatable {
    case unsupportedFile(String)
    case fileTooLarge(String)
    case requestTooLarge
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFile(name):
            String(format: AppLocalization.string("“%@” desteklenen bir belge türü değil."), name)
        case let .fileTooLarge(name):
            String(format: AppLocalization.string("“%@” 50 MB dosya sınırını aşıyor."), name)
        case .requestTooLarge:
            AppLocalization.string("Eklenen dosyaların toplamı 50 MB sınırını aşıyor.")
        case let .unreadable(name):
            String(format: AppLocalization.string("“%@” okunamadı."), name)
        }
    }
}

enum AnalysisAttachmentLoader {
    private static let supportedExtensions: Set<String> = [
        "pdf", "txt", "text", "md", "markdown", "json", "html", "htm", "xml", "rtf",
        "doc", "docx", "dot", "odt", "pages", "ppt", "pptx", "pps", "key",
        "csv", "tsv", "iif", "xls", "xlsx", "xla", "xlb", "xlc", "xlm", "xlt", "xlw",
        "eml", "log", "sql", "srt", "vtt", "ics", "vcf",
        "c", "cc", "cpp", "h", "css", "js", "mjs", "py", "swift", "java", "rb", "go"
    ]

    static func load(urls: [URL], existingBytes: Int) async throws -> [AnalysisFileAttachment] {
        try await Task.detached(priority: .userInitiated) {
            var attachments: [AnalysisFileAttachment] = []
            var totalBytes = existingBytes

            for url in urls {
                let name = url.lastPathComponent
                let ext = url.pathExtension.lowercased()
                guard supportedExtensions.contains(ext) else {
                    throw AnalysisAttachmentError.unsupportedFile(name)
                }

                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

                guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
                    throw AnalysisAttachmentError.unreadable(name)
                }
                guard data.count <= AnalysisFileAttachment.maximumRequestBytes else {
                    throw AnalysisAttachmentError.fileTooLarge(name)
                }
                totalBytes += data.count
                guard totalBytes <= AnalysisFileAttachment.maximumRequestBytes else {
                    throw AnalysisAttachmentError.requestTooLarge
                }

                attachments.append(
                    AnalysisFileAttachment(
                        filename: name,
                        mimeType: mimeType(forExtension: ext),
                        data: data
                    )
                )
            }
            return attachments
        }.value
    }

    private static func mimeType(forExtension ext: String) -> String {
        if let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime
        }
        switch ext {
        case "md", "markdown": return "text/markdown"
        case "tsv": return "text/tsv"
        case "sql": return "application/x-sql"
        case "py": return "text/x-python"
        case "swift": return "text/x-swift"
        default: return "application/octet-stream"
        }
    }
}
