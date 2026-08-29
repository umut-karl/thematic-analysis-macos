import Foundation

enum ImportError: LocalizedError {
    case unsupported
    case noRows
    case extractionFailed
    case invalidWorkbook

    var errorDescription: String? {
        switch self {
        case .unsupported: AppLocalization.string("This file type is not supported yet. Choose XLSX, CSV, or TSV.")
        case .noRows: AppLocalization.string("No transcript rows were found to import.")
        case .extractionFailed: AppLocalization.string("The Excel file could not be opened.")
        case .invalidWorkbook: AppLocalization.string("The Excel worksheet could not be read.")
        }
    }
}

enum TranscriptImporter {
    static func importFile(at url: URL) throws -> [TranscriptSegment] {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        switch url.pathExtension.lowercased() {
        case "xlsx": return try importXLSX(at: url)
        case "csv": return try importDelimited(at: url, separator: ",")
        case "tsv": return try importDelimited(at: url, separator: "\t")
        default: throw ImportError.unsupported
        }
    }

    private static func importDelimited(at url: URL, separator: Character) throws -> [TranscriptSegment] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let table = text.split(whereSeparator: \.isNewline).map { parseCSVLine(String($0), separator: separator) }
        return makeSegments(table)
    }

    private static func importXLSX(at url: URL) throws -> [TranscriptSegment] {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("ThematicAnalysis-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", url.path, "-d", temp.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ImportError.extractionFailed }

        var shared: [String] = []
        let sharedURL = temp.appendingPathComponent("xl/sharedStrings.xml")
        if FileManager.default.fileExists(atPath: sharedURL.path) {
            shared = try SharedStringsParser.parse(url: sharedURL)
        }
        let sheetURL = temp.appendingPathComponent("xl/worksheets/sheet1.xml")
        guard FileManager.default.fileExists(atPath: sheetURL.path) else { throw ImportError.invalidWorkbook }
        let rows = try WorksheetParser.parse(url: sheetURL, sharedStrings: shared)
        return makeSegments(rows)
    }

    static func makeSegments(_ table: [[String]]) -> [TranscriptSegment] {
        guard let header = table.first else { return [] }
        let normalized = header.map(normalizeHeader)
        func index(_ names: [String]) -> Int? { names.compactMap { normalized.firstIndex(of: $0) }.first }
        let orderIndex = index(["no", "order"])
        let partIndex = index(["part"])
        let speakerIndex = index(["speaker", "participant"])
        let startIndex = index(["start"])
        let endIndex = index(["end"])
        let textIndex = index(["text", "transcript", "quote"]) ?? max(0, header.count - 1)

        return table.dropFirst().enumerated().compactMap { offset, row in
            func value(_ i: Int?) -> String {
                guard let i, row.indices.contains(i) else { return "" }
                return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let text = value(textIndex)
            guard !text.isEmpty else { return nil }
            return TranscriptSegment(
                order: Int(value(orderIndex)) ?? offset + 1,
                part: Int(value(partIndex)),
                speaker: value(speakerIndex).isEmpty ? "—" : value(speakerIndex),
                start: value(startIndex),
                end: value(endIndex),
                text: text
            )
        }
    }

    private static func normalizeHeader(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased(with: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func parseCSVLine(_ line: String, separator: Character) -> [String] {
        var result: [String] = [], current = "", quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if quoted, next < line.endIndex, line[next] == "\"" {
                    current.append("\""); index = next
                } else { quoted.toggle() }
            } else if character == separator, !quoted {
                result.append(current); current = ""
            } else { current.append(character) }
            index = line.index(after: index)
        }
        result.append(current)
        return result
    }
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = [], text = "", inText = false
    static func parse(url: URL) throws -> [String] {
        let delegate = SharedStringsParser()
        guard let parser = XMLParser(contentsOf: url) else { throw ImportError.invalidWorkbook }
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? ImportError.invalidWorkbook }
        return delegate.strings
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "si" { text = "" }
        if elementName == "t" { inText = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { text += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" { inText = false }
        if elementName == "si" { strings.append(text) }
    }
}

private final class WorksheetParser: NSObject, XMLParserDelegate {
    private let shared: [String]
    private var rows: [[String]] = [], row: [String] = [], cellType = "", cellColumn = 0
    private var value = "", inlineText = "", inValue = false, inText = false
    init(shared: [String]) { self.shared = shared }

    static func parse(url: URL, sharedStrings: [String]) throws -> [[String]] {
        let delegate = WorksheetParser(shared: sharedStrings)
        guard let parser = XMLParser(contentsOf: url) else { throw ImportError.invalidWorkbook }
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? ImportError.invalidWorkbook }
        return delegate.rows
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "row" { row = [] }
        if elementName == "c" {
            cellType = attributeDict["t"] ?? ""
            cellColumn = Self.columnIndex(from: attributeDict["r"] ?? "A1")
            value = ""; inlineText = ""
        }
        if elementName == "v" { inValue = true }
        if elementName == "t" { inText = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inValue { value += string }
        if inText { inlineText += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "v" { inValue = false }
        if elementName == "t" { inText = false }
        if elementName == "c" {
            while row.count <= cellColumn { row.append("") }
            if cellType == "s", let i = Int(value), shared.indices.contains(i) { row[cellColumn] = shared[i] }
            else if cellType == "inlineStr" { row[cellColumn] = inlineText }
            else { row[cellColumn] = value }
        }
        if elementName == "row" { rows.append(row) }
    }
    private static func columnIndex(from reference: String) -> Int {
        reference.prefix(while: \.isLetter).reduce(0) { $0 * 26 + Int($1.asciiValue! - 64) } - 1
    }
}
