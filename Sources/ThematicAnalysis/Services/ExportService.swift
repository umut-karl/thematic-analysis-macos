import AppKit
import Foundation
import UniformTypeIdentifiers

struct QuoteExportRow {
    let participant: String
    let interview: String
    let speaker: String
    let time: String
    let text: String
    let themes: String
    let memo: String
}

@MainActor
enum ExportService {
    static func readProject(at url: URL) throws -> AnalysisProject {
        if url.pathExtension.lowercased() == "json" {
            return try JSONDecoder.thematic.decode(AnalysisProject.self, from: Data(contentsOf: url))
        }
        guard url.pathExtension.lowercased() == "zip" else {
            throw NSError(domain: "ThematicAnalysis.Export", code: 2, userInfo: [NSLocalizedDescriptionKey: AppLocalization.string("Choose a ZIP or JSON project backup.")])
        }
        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("ThematicAnalysis-Import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", url.path, "-d", temporaryRoot.path]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ThematicAnalysis.Export", code: 3, userInfo: [NSLocalizedDescriptionKey: AppLocalization.string("The ZIP backup could not be opened.")])
        }
        let enumerator = FileManager.default.enumerator(at: temporaryRoot, includingPropertiesForKeys: nil)
        guard let projectURL = (enumerator?.allObjects as? [URL])?.first(where: { $0.lastPathComponent == "Project-Data.json" }) else {
            throw NSError(domain: "ThematicAnalysis.Export", code: 4, userInfo: [NSLocalizedDescriptionKey: AppLocalization.string("Project-Data.json was not found in the archive.")])
        }
        return try JSONDecoder.thematic.decode(AnalysisProject.self, from: Data(contentsOf: projectURL))
    }

    static func exportQuotes(_ rows: [QuoteExportRow]) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = AppLocalization.string("Export Coded Excerpts")
        panel.nameFieldStringValue = AppLocalization.string("Coded-Excerpts.csv")
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try csvForQuotes(rows).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func exportTranscriptXLSX(_ interview: Interview) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = AppLocalization.string("Export Transcript to Excel")
        panel.nameFieldStringValue = "\(safeName(interview.participant))-\(AppLocalization.string("Transcript")).xlsx"
        if let xlsx = UTType(filenameExtension: "xlsx") {
            panel.allowedContentTypes = [xlsx]
        }
        guard panel.runModal() == .OK, let destination = panel.url else { return nil }
        try writeTranscriptXLSX(interview, to: destination)
        return destination
    }

    static func writeTranscriptXLSX(_ interview: Interview, to destination: URL) throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("ThematicAnalysis-XLSX-\(UUID().uuidString)", isDirectory: true)
        let workbook = root.appendingPathComponent("xl", isDirectory: true)
        let worksheets = workbook.appendingPathComponent("worksheets", isDirectory: true)
        let workbookRelationships = workbook.appendingPathComponent("_rels", isDirectory: true)
        let packageRelationships = root.appendingPathComponent("_rels", isDirectory: true)
        let properties = root.appendingPathComponent("docProps", isDirectory: true)

        try fileManager.createDirectory(at: worksheets, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workbookRelationships, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: packageRelationships, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: properties, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let files: [(String, URL)] = [
            (contentTypesXML, root.appendingPathComponent("[Content_Types].xml")),
            (packageRelationshipsXML, packageRelationships.appendingPathComponent(".rels")),
            (appPropertiesXML, properties.appendingPathComponent("app.xml")),
            (corePropertiesXML(title: interview.name), properties.appendingPathComponent("core.xml")),
            (workbookXML, workbook.appendingPathComponent("workbook.xml")),
            (workbookRelationshipsXML, workbookRelationships.appendingPathComponent("workbook.xml.rels")),
            (stylesXML, workbook.appendingPathComponent("styles.xml")),
            (worksheetXML(for: interview), worksheets.appendingPathComponent("sheet1.xml"))
        ]
        for (contents, url) in files {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-qr", destination.path, "."]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "ThematicAnalysis.Export",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.string("The Excel file could not be created.")]
            )
        }
    }

    static func exportProjectArchive(store: AnalysisStore) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = AppLocalization.string("Export Full Project")
        panel.nameFieldStringValue = "\(safeName(store.project.name)).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destination = panel.url else { return nil }

        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("ThematicAnalysis-Export-\(UUID().uuidString)")
        let bundle = temporaryRoot.appendingPathComponent(safeName(store.project.name), isDirectory: true)
        let transcripts = bundle.appendingPathComponent("Transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: transcripts, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let participants = [["Participant", "Interview", "Gender", "Age", "Education", "Occupation", "City/Region", "Notes", "Row", "Coding"]]
            + store.project.interviews.map { interview in
                let details = interview.participantDetails
                return [interview.participant, interview.name, details?.gender ?? "", details?.age ?? "", details?.education ?? "", details?.occupation ?? "", details?.location ?? "", details?.notes ?? "", "\(interview.segments.count)", "\(interview.codingUnits.count)"]
            }
        try csv(participants).write(to: bundle.appendingPathComponent("Participants.csv"), atomically: true, encoding: .utf8)

        let themeRows = [["Theme ID", "Parent Theme ID", "Theme Path", "Theme Narrative"]]
            + store.project.themes.map { [$0.id.uuidString, $0.parentID?.uuidString ?? "", store.themePathName(for: $0.id), $0.note ?? ""] }
        try csv(themeRows).write(to: bundle.appendingPathComponent("Theme-Tree.csv"), atomically: true, encoding: .utf8)

        var quoteRows: [QuoteExportRow] = []
        for interview in store.project.interviews {
            let transcriptRows = [["Row", "Part", "Speaker", "Start", "End", "Text"]]
                + interview.segments.map { ["\($0.order)", $0.part.map(String.init) ?? "", $0.speaker, $0.start, $0.end, $0.text] }
            try csv(transcriptRows).write(
                to: transcripts.appendingPathComponent("\(safeName(interview.participant))-Transcript.csv"),
                atomically: true,
                encoding: .utf8
            )
            for unit in interview.codingUnits {
                let segments = interview.segments.filter { unit.segmentIDs.contains($0.id) }.sorted { $0.order < $1.order }
                quoteRows.append(QuoteExportRow(
                    participant: interview.participant,
                    interview: interview.name,
                    speaker: segments.first?.speaker ?? "",
                    time: "\(segments.first?.start ?? "")–\(segments.last?.end ?? "")",
                    text: segments.map(\.text).joined(separator: " "),
                    themes: unit.themeIDs.map(store.themePathName).sorted().joined(separator: " | "),
                    memo: unit.memo
                ))
            }
        }
        try csvForQuotes(quoteRows).write(to: bundle.appendingPathComponent("Coded-Excerpts.csv"), atomically: true, encoding: .utf8)
        try JSONEncoder.thematic.encode(store.project).write(to: bundle.appendingPathComponent("Project-Data.json"), options: .atomic)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", bundle.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ThematicAnalysis.Export", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: AppLocalization.string("The ZIP archive could not be created.")])
        }
        return destination
    }

    private static func csvForQuotes(_ rows: [QuoteExportRow]) -> String {
        csv([["Participant", "Interview", "Speaker", "Time", "Excerpt", "Theme Paths", "Analytic Note"]]
            + rows.map { [$0.participant, $0.interview, $0.speaker, $0.time, $0.text, $0.themes, $0.memo] })
    }

    private static func csv(_ rows: [[String]]) -> String {
        "\u{FEFF}" + rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n")
    }

    private static func escape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func safeName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return value.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func worksheetXML(for interview: Interview) -> String {
        let headers = ["Row", "Part", "Speaker", "Start", "End", "Text"]
        let headerCells = headers.enumerated().map { index, value in
            inlineCell(column: index, row: 1, value: value, style: 1)
        }.joined()

        let sortedSegments = interview.segments.sorted { $0.order < $1.order }
        let speakerIndices = SpeakerPalette.indices(for: sortedSegments.map(\.speaker))
        let dataRows = sortedSegments.enumerated().map { index, segment in
            let row = index + 2
            let speakerIndex = SpeakerPalette.index(for: segment.speaker, in: speakerIndices)
            let bodyStyle = speakerIndex.map { 4 + ($0 * 2) } ?? 2
            let wrappedStyle = speakerIndex.map { 5 + ($0 * 2) } ?? 3
            let textLength = max(segment.text.count, 1)
            let estimatedLines = max(1, Int(ceil(Double(textLength) / 82.0)))
            let height = min(120, max(21, estimatedLines * 15 + 6))
            let cells = [
                numberCell(column: 0, row: row, value: segment.order, style: bodyStyle),
                segment.part.map { numberCell(column: 1, row: row, value: $0, style: bodyStyle) } ?? inlineCell(column: 1, row: row, value: "", style: bodyStyle),
                inlineCell(column: 2, row: row, value: segment.speaker, style: bodyStyle),
                inlineCell(column: 3, row: row, value: segment.start, style: bodyStyle),
                inlineCell(column: 4, row: row, value: segment.end, style: bodyStyle),
                inlineCell(column: 5, row: row, value: segment.text, style: wrappedStyle)
            ].joined()
            return "<row r=\"\(row)\" ht=\"\(height)\" customHeight=\"1\">\(cells)</row>"
        }.joined()

        let lastRow = max(interview.segments.count + 1, 1)
        return xmlHeader + """
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
          <cols>
            <col min="1" max="1" width="8" customWidth="1"/>
            <col min="2" max="2" width="8" customWidth="1"/>
            <col min="3" max="3" width="22" customWidth="1"/>
            <col min="4" max="5" width="14" customWidth="1"/>
            <col min="6" max="6" width="90" customWidth="1"/>
          </cols>
          <sheetData><row r="1" ht="24" customHeight="1">\(headerCells)</row>\(dataRows)</sheetData>
          <autoFilter ref="A1:F\(lastRow)"/>
          <pageMargins left="0.3" right="0.3" top="0.5" bottom="0.5" header="0.2" footer="0.2"/>
        </worksheet>
        """
    }

    private static func inlineCell(column: Int, row: Int, value: String, style: Int) -> String {
        let reference = "\(columnName(column))\(row)"
        return "<c r=\"\(reference)\" s=\"\(style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xmlEscaped(value))</t></is></c>"
    }

    private static func numberCell(column: Int, row: Int, value: Int, style: Int) -> String {
        "<c r=\"\(columnName(column))\(row)\" s=\"\(style)\"><v>\(value)</v></c>"
    }

    private static func columnName(_ zeroBasedIndex: Int) -> String {
        var index = zeroBasedIndex + 1
        var result = ""
        while index > 0 {
            index -= 1
            result = String(UnicodeScalar(65 + index % 26)!) + result
            index /= 26
        }
        return result
    }

    private static func xmlEscaped(_ value: String) -> String {
        let validScalars = value.unicodeScalars.filter { scalar in
            scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D || scalar.value >= 0x20
        }
        return String(String.UnicodeScalarView(validScalars))
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"

    private static let contentTypesXML = xmlHeader + """
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
      <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
      <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
    </Types>
    """

    private static let packageRelationshipsXML = xmlHeader + """
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
      <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
    </Relationships>
    """

    private static let workbookXML = xmlHeader + """
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets><sheet name="Transcript" sheetId="1" r:id="rId1"/></sheets>
    </workbook>
    """

    private static let workbookRelationshipsXML = xmlHeader + """
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    private static var stylesXML: String {
        let speakerFills = SpeakerPalette.swatches.map {
            "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"\($0.backgroundARGB)\"/><bgColor indexed=\"64\"/></patternFill></fill>"
        }.joined()
        let speakerStyles = SpeakerPalette.swatches.enumerated().map { index, _ in
            let fillID = index + 3
            return """
            <xf numFmtId="0" fontId="0" fillId="\(fillID)" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top"/></xf>
            <xf numFmtId="0" fontId="0" fillId="\(fillID)" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
            """
        }.joined()
        return xmlHeader + """
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <fonts count="2">
        <font><sz val="11"/><color theme="1"/><name val="Aptos"/><family val="2"/></font>
        <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Aptos Display"/><family val="2"/></font>
      </fonts>
      <fills count="\(3 + SpeakerPalette.swatches.count)"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF2563EB"/><bgColor indexed="64"/></patternFill></fill>\(speakerFills)</fills>
      <borders count="2"><border/><border><left style="thin"><color rgb="FFD9DEE8"/></left><right style="thin"><color rgb="FFD9DEE8"/></right><top style="thin"><color rgb="FFD9DEE8"/></top><bottom style="thin"><color rgb="FFD9DEE8"/></bottom><diagonal/></border></borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="\(4 + SpeakerPalette.swatches.count * 2)">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
        <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
        <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top"/></xf>
        <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
        \(speakerStyles)
      </cellXfs>
      <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """
    }

    private static let appPropertiesXML = xmlHeader + """
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>Thematic Analysis</Application></Properties>
    """

    private static func corePropertiesXML(title: String) -> String {
        xmlHeader + """
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>\(xmlEscaped(title))</dc:title><dc:creator>Thematic Analysis</dc:creator></cp:coreProperties>
        """
    }
}
