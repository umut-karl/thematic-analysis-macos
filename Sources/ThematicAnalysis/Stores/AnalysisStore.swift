import AppKit
import Foundation
import SwiftUI

@MainActor
final class AnalysisStore: ObservableObject {
    @Published var project: AnalysisProject
    @Published var selectedInterviewID: UUID?
    @Published var selectedSegmentIDs: Set<UUID> = []
    @Published var selectedThemeIDs: Set<UUID> = []
    @Published var lastMessage = "Ready"
    @Published var isImporting = false

    private let fileManager = FileManager.default
    private let saveURL: URL
    private let backupDirectory: URL
    private var pendingSaveTask: Task<Void, Never>?

    init(storageRoot: URL? = nil, initialProject: AnalysisProject? = nil) {
        let base = storageRoot ?? Self.defaultStorageRoot()
        saveURL = base.appendingPathComponent("active-project.json")
        backupDirectory = base.appendingPathComponent("Backups", isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: saveURL),
           let saved = try? JSONDecoder.thematic.decode(AnalysisProject.self, from: data) {
            project = saved
        } else {
            project = initialProject ?? AnalysisProject(
                name: "Untitled Project",
                interviews: [],
                themes: []
            )
        }
        selectedInterviewID = project.interviews.first?.id
        if initialProject != nil {
            try? JSONEncoder.thematic.encode(project).write(to: saveURL, options: .atomic)
        }
    }

    var selectedInterview: Interview? {
        guard let selectedInterviewID else { return nil }
        return project.interviews.first(where: { $0.id == selectedInterviewID })
    }

    var selectedSegments: [TranscriptSegment] {
        selectedInterview?.segments.filter { selectedSegmentIDs.contains($0.id) }
            .sorted { $0.order < $1.order } ?? []
    }

    var selectedText: String { selectedSegments.map(\.text).joined(separator: " ") }

    func themeName(_ id: UUID) -> String {
        project.themes.first(where: { $0.id == id })?.name ?? "Deleted theme"
    }

    func themeNote(_ id: UUID) -> String {
        project.themes.first(where: { $0.id == id })?.note ?? ""
    }

    func updateThemeNote(_ id: UUID, note: String) {
        guard let index = project.themes.firstIndex(where: { $0.id == id }) else { return }
        project.themes[index].note = note.isEmpty ? nil : note
        schedulePersist()
    }

    func themePath(for id: UUID) -> [ThemeNode] {
        var path: [ThemeNode] = []
        var current = project.themes.first(where: { $0.id == id })
        var visited: Set<UUID> = []
        while let node = current, !visited.contains(node.id) {
            visited.insert(node.id)
            path.append(node)
            current = node.parentID.flatMap { parent in project.themes.first(where: { $0.id == parent }) }
        }
        return path.reversed()
    }

    func themePathName(for id: UUID) -> String {
        themePath(for: id).map(\.name).joined(separator: " › ")
    }

    func theme(_ candidateID: UUID, isDescendantOf ancestorID: UUID) -> Bool {
        themePath(for: candidateID).contains(where: { $0.id == ancestorID })
    }

    func children(of parentID: UUID?) -> [ThemeNode] {
        project.themes.filter { $0.parentID == parentID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func codingUnit(containing segmentID: UUID) -> CodingUnit? {
        selectedInterview?.codingUnits.first { $0.segmentIDs.contains(segmentID) }
    }

    func segment(_ id: UUID) -> TranscriptSegment? {
        selectedInterview?.segments.first(where: { $0.id == id })
    }

    func updateSegment(_ id: UUID, change: (inout TranscriptSegment) -> Void) {
        guard let interviewIndex = selectedInterviewIndex,
              let segmentIndex = project.interviews[interviewIndex].segments.firstIndex(where: { $0.id == id }) else { return }
        change(&project.interviews[interviewIndex].segments[segmentIndex])
        schedulePersist()
    }

    func insertTranscriptRow() {
        guard let interviewIndex = selectedInterviewIndex else { return }
        let segments = project.interviews[interviewIndex].segments
        let selectedOrders = segments.filter { selectedSegmentIDs.contains($0.id) }.map(\.order)
        let insertionOrder = (selectedOrders.max() ?? segments.map(\.order).max() ?? 0) + 1
        let newRow = TranscriptSegment(order: insertionOrder, part: nil, speaker: "", start: "", end: "", text: "")
        let insertionIndex = segments.firstIndex(where: { $0.order >= insertionOrder }) ?? segments.endIndex
        project.interviews[interviewIndex].segments.insert(newRow, at: insertionIndex)
        renumberSegments(interviewIndex: interviewIndex)
        selectedSegmentIDs = [newRow.id]
        persist(message: "New transcript row added")
    }

    func mergeSelectedTranscriptRows() {
        guard selectedSegmentIDs.count >= 2, let interviewIndex = selectedInterviewIndex else { return }
        let selected = project.interviews[interviewIndex].segments
            .filter { selectedSegmentIDs.contains($0.id) }.sorted { $0.order < $1.order }
        guard let first = selected.first else { return }
        let removedIDs = Set(selected.dropFirst().map(\.id))
        let speakers = Array(Set(selected.map(\.speaker).filter { !$0.isEmpty })).sorted()

        if let firstIndex = project.interviews[interviewIndex].segments.firstIndex(where: { $0.id == first.id }) {
            project.interviews[interviewIndex].segments[firstIndex].text = selected.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
            project.interviews[interviewIndex].segments[firstIndex].start = first.start
            project.interviews[interviewIndex].segments[firstIndex].end = selected.last?.end ?? first.end
            project.interviews[interviewIndex].segments[firstIndex].speaker = speakers.joined(separator: " / ")
        }
        project.interviews[interviewIndex].segments.removeAll { removedIDs.contains($0.id) }
        for unitIndex in project.interviews[interviewIndex].codingUnits.indices {
            let oldIDs = project.interviews[interviewIndex].codingUnits[unitIndex].segmentIDs
            if oldIDs.contains(where: removedIDs.contains) {
                project.interviews[interviewIndex].codingUnits[unitIndex].segmentIDs = Array(Set(oldIDs.filter { !removedIDs.contains($0) } + [first.id]))
            }
        }
        renumberSegments(interviewIndex: interviewIndex)
        selectedSegmentIDs = [first.id]
        persist(message: "\(selected.count) rows merged into one row")
    }

    func deleteSelectedTranscriptRows() {
        guard !selectedSegmentIDs.isEmpty, let interviewIndex = selectedInterviewIndex else { return }
        let deleted = selectedSegmentIDs
        project.interviews[interviewIndex].segments.removeAll { deleted.contains($0.id) }
        for unitIndex in project.interviews[interviewIndex].codingUnits.indices {
            project.interviews[interviewIndex].codingUnits[unitIndex].segmentIDs.removeAll { deleted.contains($0) }
        }
        project.interviews[interviewIndex].codingUnits.removeAll { $0.segmentIDs.isEmpty }
        renumberSegments(interviewIndex: interviewIndex)
        selectedSegmentIDs.removeAll()
        persist(message: "\(deleted.count) transcript rows deleted")
    }

    func assignSelection(memo: String) {
        _ = saveCodingSelection(themeIDs: selectedThemeIDs, memo: memo, keepSelection: false)
    }

    @discardableResult
    func saveCodingSelection(themeIDs: Set<UUID>, memo: String, keepSelection: Bool) -> UUID? {
        guard !selectedSegmentIDs.isEmpty, !themeIDs.isEmpty,
              let interviewIndex = selectedInterviewIndex else { return nil }
        let segmentIDs = selectedSegments.map(\.id)
        let segmentSet = Set(segmentIDs)
        let cleanMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let unitID: UUID
        if let unitIndex = project.interviews[interviewIndex].codingUnits.firstIndex(where: { Set($0.segmentIDs) == segmentSet }) {
            project.interviews[interviewIndex].codingUnits[unitIndex].themeIDs.formUnion(themeIDs)
            if !cleanMemo.isEmpty { project.interviews[interviewIndex].codingUnits[unitIndex].memo = cleanMemo }
            unitID = project.interviews[interviewIndex].codingUnits[unitIndex].id
            selectedThemeIDs = project.interviews[interviewIndex].codingUnits[unitIndex].themeIDs
        } else {
            let unit = CodingUnit(segmentIDs: segmentIDs, themeIDs: themeIDs, memo: cleanMemo)
            project.interviews[interviewIndex].codingUnits.append(unit)
            unitID = unit.id
            selectedThemeIDs = themeIDs
        }
        if !keepSelection {
            selectedSegmentIDs.removeAll()
            selectedThemeIDs.removeAll()
        }
        persist(message: keepSelection ? "Theme saved; you can keep coding the same selection" : "Coding unit saved")
        return unitID
    }

    func themeIDsForCurrentSelection() -> Set<UUID> {
        guard let interview = selectedInterview, !selectedSegmentIDs.isEmpty else { return [] }
        let selected = selectedSegmentIDs
        return interview.codingUnits.first(where: { Set($0.segmentIDs) == selected })?.themeIDs ?? []
    }

    func removeThemeFromCurrentSelection(_ themeID: UUID) {
        guard let interviewIndex = selectedInterviewIndex else { return }
        let selected = selectedSegmentIDs
        guard let unitIndex = project.interviews[interviewIndex].codingUnits.firstIndex(where: { Set($0.segmentIDs) == selected }) else { return }
        project.interviews[interviewIndex].codingUnits[unitIndex].themeIDs.remove(themeID)
        selectedThemeIDs.remove(themeID)
        if project.interviews[interviewIndex].codingUnits[unitIndex].themeIDs.isEmpty {
            project.interviews[interviewIndex].codingUnits.remove(at: unitIndex)
        }
        persist(message: "Theme assignment removed")
    }

    func removeThemeAssignments(unitID: UUID, interviewID: UUID, matching ancestorID: UUID) {
        guard let interviewIndex = project.interviews.firstIndex(where: { $0.id == interviewID }),
              let unitIndex = project.interviews[interviewIndex].codingUnits.firstIndex(where: { $0.id == unitID }) else { return }
        let retained = project.interviews[interviewIndex].codingUnits[unitIndex].themeIDs.filter { !theme($0, isDescendantOf: ancestorID) }
        project.interviews[interviewIndex].codingUnits[unitIndex].themeIDs = Set(retained)
        if project.interviews[interviewIndex].codingUnits[unitIndex].themeIDs.isEmpty {
            project.interviews[interviewIndex].codingUnits.remove(at: unitIndex)
        }
        persist(message: "Theme assignment removed")
    }

    func replaceThemeAssignments(unitID: UUID, interviewID: UUID, matching ancestorID: UUID, with replacementID: UUID) {
        guard let interviewIndex = project.interviews.firstIndex(where: { $0.id == interviewID }),
              let unitIndex = project.interviews[interviewIndex].codingUnits.firstIndex(where: { $0.id == unitID }) else { return }
        let retained = project.interviews[interviewIndex].codingUnits[unitIndex].themeIDs.filter { !theme($0, isDescendantOf: ancestorID) }
        project.interviews[interviewIndex].codingUnits[unitIndex].themeIDs = Set(retained)
        project.interviews[interviewIndex].codingUnits[unitIndex].themeIDs.insert(replacementID)
        persist(message: "Theme assignment updated")
    }

    func removeCodingUnit(_ id: UUID, interviewID: UUID) {
        guard let index = project.interviews.firstIndex(where: { $0.id == interviewID }) else { return }
        project.interviews[index].codingUnits.removeAll { $0.id == id }
        persist(message: "Coding removed")
    }

    @discardableResult
    func addTheme(name: String, parentID: UUID?) -> UUID? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let colorIndex = parentID.flatMap { id in project.themes.first(where: { $0.id == id })?.colorIndex }
            ?? (children(of: nil).count % 6)
        let node = ThemeNode(name: clean, parentID: parentID, colorIndex: colorIndex)
        project.themes.append(node)
        persist(message: "Theme “\(clean)” added")
        return node.id
    }

    func importTranscript(from url: URL) async {
        isImporting = true
        defer { isImporting = false }
        do {
            let rows = try TranscriptImporter.importFile(at: url)
            guard !rows.isEmpty else { throw ImportError.noRows }
            let displayName = url.deletingPathExtension().lastPathComponent
            let interview = Interview(name: displayName, participant: displayName, participantDetails: nil, segments: rows)
            project.interviews.append(interview)
            selectedInterviewID = interview.id
            persist(message: "\(rows.count) rows imported")
        } catch {
            lastMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func createParticipant(name: String, details: ParticipantDetails, transcriptURL: URL) async -> Bool {
        isImporting = true
        defer { isImporting = false }
        do {
            let rows = try TranscriptImporter.importFile(at: transcriptURL)
            guard !rows.isEmpty else { throw ImportError.noRows }
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let interview = Interview(
                name: "\(cleanName) Transcript",
                participant: cleanName,
                participantDetails: details,
                segments: rows
            )
            project.interviews.append(interview)
            selectedInterviewID = interview.id
            persist(message: "\(cleanName) added · \(rows.count) rows imported")
            return true
        } catch {
            lastMessage = "Could not add participant: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func updateParticipant(
        interviewID: UUID,
        participantName: String,
        interviewName: String,
        details: ParticipantDetails
    ) -> Bool {
        let cleanParticipantName = participantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanParticipantName.isEmpty else {
            lastMessage = "Participant name cannot be empty"
            return false
        }
        guard let index = project.interviews.firstIndex(where: { $0.id == interviewID }) else {
            lastMessage = "Participant not found"
            return false
        }

        let cleanInterviewName = interviewName.trimmingCharacters(in: .whitespacesAndNewlines)
        project.interviews[index].participant = cleanParticipantName
        project.interviews[index].name = cleanInterviewName.isEmpty
            ? "\(cleanParticipantName) Transcript"
            : cleanInterviewName
        project.interviews[index].participantDetails = details
        persist(message: "\(cleanParticipantName) details updated")
        return true
    }

    @discardableResult
    func createTranscribedCase(
        participantName: String,
        interviewName: String,
        transcript: String,
        sourceFileName: String,
        model: String
    ) -> UUID? {
        let cleanParticipant = participantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanParticipant.isEmpty else {
            lastMessage = "A participant name is required for a new case"
            return nil
        }
        let segments = TranscriptionSegmenter.segments(from: transcript)
        guard !segments.isEmpty else {
            lastMessage = "A case could not be created because the transcript is empty"
            return nil
        }
        let cleanInterviewName = interviewName.trimmingCharacters(in: .whitespacesAndNewlines)
        var details = ParticipantDetails()
        details.notes = "Audio transcription · Model: \(model) · Source: \(sourceFileName)"
        let interview = Interview(
            name: cleanInterviewName.isEmpty ? "\(cleanParticipant) Transcript" : cleanInterviewName,
            participant: cleanParticipant,
            participantDetails: details,
            segments: segments
        )
        project.interviews.append(interview)
        selectedInterviewID = interview.id
        selectedSegmentIDs.removeAll()
        selectedThemeIDs.removeAll()
        persist(message: "Added \(segments.count) GPT transcript rows for \(cleanParticipant)")
        return interview.id
    }

    @discardableResult
    func createDiarizedCase(
        participantName: String,
        interviewName: String,
        participantDetails: ParticipantDetails? = nil,
        diarizedSegments: [OpenAITranscriptionSegment],
        speakerNames: [String: String],
        sourceFileName: String,
        model: String
    ) -> UUID? {
        let cleanParticipant = participantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanParticipant.isEmpty else {
            lastMessage = "A participant name is required for a new case"
            return nil
        }

        let segments = diarizedSegments.enumerated().compactMap { index, source -> TranscriptSegment? in
            let cleanText = source.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanText.isEmpty else { return nil }
            let mappedSpeaker = speakerNames[source.speaker]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displaySpeaker = mappedSpeaker.flatMap { $0.isEmpty ? nil : $0 } ?? source.speaker
            return TranscriptSegment(
                order: index + 1,
                part: nil,
                speaker: displaySpeaker,
                start: Self.formatAudioTime(source.start, rounding: .down),
                end: Self.formatAudioTime(source.end, rounding: .up),
                text: cleanText
            )
        }
        guard !segments.isEmpty else {
            lastMessage = "A case could not be created because the timed transcript is empty"
            return nil
        }

        let cleanInterviewName = interviewName.trimmingCharacters(in: .whitespacesAndNewlines)
        var details = participantDetails ?? ParticipantDetails()
        let provenance = "Audio transcription · Model: \(model) · Source: \(sourceFileName)"
        let cleanNotes = details.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        details.notes = cleanNotes.isEmpty ? provenance : "\(cleanNotes)\n\(provenance)"
        let interview = Interview(
            name: cleanInterviewName.isEmpty ? "\(cleanParticipant) Transcript" : cleanInterviewName,
            participant: cleanParticipant,
            participantDetails: details,
            segments: segments
        )
        project.interviews.append(interview)
        selectedInterviewID = interview.id
        selectedSegmentIDs.removeAll()
        selectedThemeIDs.removeAll()
        persist(message: "Added \(segments.count) timed, speaker-labeled rows for \(cleanParticipant)")
        return interview.id
    }

    func importThemes(from url: URL) async {
        isImporting = true
        defer { isImporting = false }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let imported = ThemeMarkdownImporter.parse(markdown)
            guard !imported.isEmpty else { throw ImportError.noRows }
            project.themes.append(contentsOf: imported)
            persist(message: "\(imported.count) theme nodes imported")
        } catch {
            lastMessage = "Could not import theme list: \(error.localizedDescription)"
        }
    }

    func restoreProject(from url: URL) async {
        isImporting = true
        defer { isImporting = false }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            createBackup()
            project = try ExportService.readProject(at: url)
            selectedInterviewID = project.interviews.first?.id
            selectedSegmentIDs.removeAll()
            selectedThemeIDs.removeAll()
            persist(message: "Project backup restored")
        } catch {
            lastMessage = "Could not open backup: \(error.localizedDescription)"
        }
    }

    func createBackup() {
        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let url = backupDirectory.appendingPathComponent("ThematicAnalysis_\(formatter.string(from: .now)).json")
            let data = try JSONEncoder.thematic.encode(project)
            try data.write(to: url, options: .atomic)
            lastMessage = "Backup created: \(url.lastPathComponent)"
        } catch {
            lastMessage = "Could not create backup: \(error.localizedDescription)"
        }
    }

    func persist(message: String = "Changes saved") {
        do {
            project.updatedAt = .now
            try JSONEncoder.thematic.encode(project).write(to: saveURL, options: .atomic)
            lastMessage = message
        } catch {
            lastMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func schedulePersist() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    private func renumberSegments(interviewIndex: Int) {
        project.interviews[interviewIndex].segments.sort { $0.order < $1.order }
        for index in project.interviews[interviewIndex].segments.indices {
            project.interviews[interviewIndex].segments[index].order = index + 1
        }
    }

    private static func formatAudioTime(_ seconds: Double, rounding: FloatingPointRoundingRule) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(rounding)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private var selectedInterviewIndex: Int? {
        guard let selectedInterviewID else { return nil }
        return project.interviews.firstIndex(where: { $0.id == selectedInterviewID })
    }

    private static func defaultStorageRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["THEMATIC_ANALYSIS_DATA_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ThematicAnalysis", isDirectory: true)
    }

}

extension JSONEncoder {
    static var thematic: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var thematic: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
