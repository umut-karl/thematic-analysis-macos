import Foundation

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
            AppLocalization.string("No OpenAI API key was entered.")
        case let .unsupportedFileType(fileExtension):
            "\(fileExtension.uppercased()) is not supported. Choose MP3, MP4, MPEG, MPGA, M4A, WAV, or WEBM."
        case let .fileTooLarge(bytes):
            "The audio file is \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)). The OpenAI transcription file limit is 25 MB."
        case .unreadableFile:
            AppLocalization.string("The audio file could not be read. Make sure it is still accessible.")
        case .invalidResponse:
            AppLocalization.string("OpenAI did not return a valid transcript response.")
        case let .api(statusCode, message):
            "OpenAI request failed (HTTP \(statusCode)): \(message)"
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
            throw OpenAITranscriptionError.unsupportedFileType(fileExtension.isEmpty ? "file" : fileExtension)
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
                ?? "Unknown API error"
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
    private static let key = "openAIAPIKey"

    static func load() -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }

    static func save(_ apiKey: String) throws {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanKey.isEmpty {
            delete()
            return
        }
        UserDefaults.standard.set(cleanKey, forKey: key)
    }

    static func delete() {
        UserDefaults.standard.removeObject(forKey: key)
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
