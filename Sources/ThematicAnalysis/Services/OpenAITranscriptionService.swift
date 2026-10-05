import Foundation
import Security

enum OpenAITranscriptionError: LocalizedError, Equatable {
    case missingAPIKey
    case unsupportedFileType(String)
    case fileTooLarge(Int64)
    case unreadableFile
    case invalidResponse
    case api(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            AppLocalization.string("OpenAI API anahtarı girilmedi.")
        case let .unsupportedFileType(fileExtension):
            AppLocalization.language == .english
                ? "\(fileExtension.uppercased()) is not supported. Choose MP3, MP4, MPEG, MPGA, M4A, WAV, or WEBM."
                : "\(fileExtension.uppercased()) biçimi desteklenmiyor. MP3, MP4, MPEG, MPGA, M4A, WAV veya WEBM seçin."
        case let .fileTooLarge(bytes):
            AppLocalization.language == .english
                ? "The audio file is \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)). The OpenAI transcription file limit is 25 MB."
                : "Ses dosyası \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)). OpenAI dosya transkripsiyonu için üst sınır 25 MB."
        case .unreadableFile:
            AppLocalization.string("Ses dosyası okunamadı. Dosyanın hâlâ erişilebilir olduğundan emin olun.")
        case .invalidResponse:
            AppLocalization.string("OpenAI geçerli bir transkript yanıtı döndürmedi.")
        case let .api(statusCode, message):
            AppLocalization.language == .english
                ? "OpenAI request failed (HTTP \(statusCode)): \(message)"
                : "OpenAI isteği başarısız (HTTP \(statusCode)): \(message)"
        }
    }
}

struct OpenAITranscriptionSegment: Identifiable, Decodable, Equatable {
    let speaker: String
    let start: Double
    let end: Double
    let text: String

    var id: String { "\(speaker)|\(start)|\(end)" }
}

struct OpenAITranscriptionResult: Equatable {
    let segments: [OpenAITranscriptionSegment]
    let model: String

    var text: String { segments.map(\.text).joined(separator: " ") }
    var speakers: [String] {
        var seen: Set<String> = []
        return segments.compactMap { seen.insert($0.speaker).inserted ? $0.speaker : nil }
    }
}

enum OpenAITranscriptionService {
    static let model = "gpt-4o-transcribe-diarize"
    static let maximumFileSize: Int64 = 25 * 1_024 * 1_024
    static let supportedExtensions: Set<String> = ["mp3", "mp4", "mpeg", "mpga", "m4a", "wav", "webm"]

    private struct Response: Decodable { let segments: [OpenAITranscriptionSegment] }

    private struct ErrorEnvelope: Decodable {
        struct APIError: Decodable { let message: String }
        let error: APIError
    }

    static func transcribe(
        audioURL: URL,
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> OpenAITranscriptionResult {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { throw OpenAITranscriptionError.missingAPIKey }

        let fileExtension = audioURL.pathExtension.lowercased()
        guard supportedExtensions.contains(fileExtension) else {
            throw OpenAITranscriptionError.unsupportedFileType(fileExtension.isEmpty ? "dosya" : fileExtension)
        }

        let didAccess = audioURL.startAccessingSecurityScopedResource()
        defer { if didAccess { audioURL.stopAccessingSecurityScopedResource() } }

        let fileSize = try audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0
        guard fileSize <= maximumFileSize else { throw OpenAITranscriptionError.fileTooLarge(fileSize) }
        guard let audioData = try? Data(contentsOf: audioURL) else { throw OpenAITranscriptionError.unreadableFile }

        let boundary = "ThematicAnalysis-\(UUID().uuidString)"
        var body = MultipartFormData(boundary: boundary)
        body.appendField(name: "model", value: model)
        body.appendField(name: "response_format", value: "diarized_json")
        body.appendField(name: "chunking_strategy", value: "auto")
        body.appendFile(
            name: "file",
            filename: audioURL.lastPathComponent,
            mimeType: mimeType(for: fileExtension),
            data: audioData
        )

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15 * 60
        request.httpBody = body.finalized()

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAITranscriptionError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error.message)
                ?? String(data: data, encoding: .utf8)
                ?? "Bilinmeyen API hatası"
            throw OpenAITranscriptionError.api(statusCode: http.statusCode, message: message)
        }
        let segments = try decodeDiarizedResponse(data)
        return OpenAITranscriptionResult(segments: segments, model: model)
    }

    static func decodeDiarizedResponse(_ data: Data) throws -> [OpenAITranscriptionSegment] {
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              !decoded.segments.isEmpty else {
            throw OpenAITranscriptionError.invalidResponse
        }
        return decoded.segments
    }

    private static func mimeType(for fileExtension: String) -> String {
        switch fileExtension {
        case "mp3", "mpga": "audio/mpeg"
        case "mp4": "audio/mp4"
        case "mpeg": "audio/mpeg"
        case "m4a": "audio/mp4"
        case "wav": "audio/wav"
        case "webm": "audio/webm"
        default: "application/octet-stream"
        }
    }
}

struct MultipartFormData {
    let boundary: String
    private(set) var data = Data()

    mutating func appendField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func appendFile(name: String, filename: String, mimeType: String, data fileData: Data) {
        let safeFilename = filename
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(safeFilename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")
    }

    func finalized() -> Data {
        var result = data
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }

    private mutating func append(_ string: String) {
        data.append(Data(string.utf8))
    }
}

enum OpenAIAPIKeyStore {
    private static let legacyKey = "openAIAPIKey"
    private static let service = "com.umutkarlikli.ThematicAnalysis.openai"
    private static let account = "OpenAIAPIKey"

    static func load() -> String {
        var query: [String: Any] = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let key = String(data: data, encoding: .utf8), !key.isEmpty {
            return key
        }

        // Preserve existing installations: migrate the former UserDefaults
        // value into Keychain the first time the updated app reads it.
        let legacy = UserDefaults.standard.string(forKey: legacyKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !legacy.isEmpty else { return "" }
        try? save(legacy)
        UserDefaults.standard.removeObject(forKey: legacyKey)
        return legacy
    }

    static func save(_ apiKey: String) throws {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanKey.isEmpty {
            delete()
            return
        }
        let data = Data(cleanKey.utf8)
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw keychainError(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw keychainError(updateStatus)
        }
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func keychainError(_ status: OSStatus) -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Keychain hatası"]
        )
    }
}

enum TranscriptionSegmenter {
    static func segments(from transcript: String, targetCharacterCount: Int = 700) -> [TranscriptSegment] {
        let cleanText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return [] }

        let paragraphs = cleanText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let blocks = paragraphs.count > 1 ? paragraphs : sentenceBlocks(from: cleanText, targetCharacterCount: targetCharacterCount)

        return blocks.enumerated().map { index, text in
            TranscriptSegment(order: index + 1, part: nil, speaker: "—", start: "", end: "", text: text)
        }
    }

    private static func sentenceBlocks(from text: String, targetCharacterCount: Int) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
        }
        guard !sentences.isEmpty else { return [text] }

        var blocks: [String] = []
        var current = ""
        for sentence in sentences {
            if !current.isEmpty, current.count + sentence.count + 1 > targetCharacterCount {
                blocks.append(current)
                current = sentence
            } else {
                current += current.isEmpty ? sentence : " \(sentence)"
            }
        }
        if !current.isEmpty { blocks.append(current) }
        return blocks
    }
}
