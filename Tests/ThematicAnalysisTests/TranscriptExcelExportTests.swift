import Foundation
import XCTest
@testable import ThematicAnalysis

final class TranscriptExcelExportTests: XCTestCase {
    @MainActor
    func testXLSXExportRoundTripsSpeakerTimesAndText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ThematicAnalysis-XLSX-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let interview = Interview(
            name: "Participant A Diarized Interview",
            participant: "Participant A",
            segments: [
                TranscriptSegment(order: 1, part: nil, speaker: "Interviewer", start: "00:00", end: "00:05", text: "Welcome."),
                TranscriptSegment(order: 2, part: 1, speaker: "Participant A", start: "00:05", end: "01:06", text: "Thank you & glad to be here.")
            ]
        )
        let output = root.appendingPathComponent("Participant-A-Transcript.xlsx")

        try ExportService.writeTranscriptXLSX(interview, to: output)

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let imported = try TranscriptImporter.importFile(at: output)
        XCTAssertEqual(imported.map(\.speaker), ["Interviewer", "Participant A"])
        XCTAssertEqual(imported.map(\.start), ["00:00", "00:05"])
        XCTAssertEqual(imported.map(\.end), ["00:05", "01:06"])
        XCTAssertEqual(imported.map(\.text), ["Welcome.", "Thank you & glad to be here."])
        XCTAssertEqual(imported.map(\.part), [nil, 1])

        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-qq", output.path, "-d", extracted.path]
        try unzip.run()
        unzip.waitUntilExit()
        XCTAssertEqual(unzip.terminationStatus, 0)

        let sheetXML = try String(contentsOf: extracted.appendingPathComponent("xl/worksheets/sheet1.xml"), encoding: .utf8)
        let stylesXML = try String(contentsOf: extracted.appendingPathComponent("xl/styles.xml"), encoding: .utf8)
        XCTAssertTrue(sheetXML.contains("r=\"A2\" s=\"4\""))
        XCTAssertTrue(sheetXML.contains("r=\"A3\" s=\"6\""))
        XCTAssertTrue(stylesXML.contains("rgb=\"FFEAF2FF\""))
        XCTAssertTrue(stylesXML.contains("rgb=\"FFFFF0E6\""))
    }

    func testSpeakerPaletteAssignsStableDistinctColorsByFirstAppearance() {
        let indices = SpeakerPalette.indices(for: ["Interviewer", "Participant A", "Interviewer", "Third person"])
        XCTAssertEqual(SpeakerPalette.index(for: "Interviewer", in: indices), 0)
        XCTAssertEqual(SpeakerPalette.index(for: "Participant A", in: indices), 1)
        XCTAssertEqual(SpeakerPalette.index(for: "Third person", in: indices), 2)
    }
}
