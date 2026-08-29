import SwiftUI

struct CodedQuotesView: View {
    @ObservedObject var store: AnalysisStore
    @State private var query = ""
    @State private var participantFilter: UUID?
    @State private var speakerFilter: String?
    @State private var selectedThemeFilter: UUID?
    @State private var includeDescendants = true

    private var allEntries: [QuoteEntry] {
        store.project.interviews.flatMap { interview in
            interview.codingUnits.map { unit in
                let segments = interview.segments.filter { unit.segmentIDs.contains($0.id) }.sorted { $0.order < $1.order }
                return QuoteEntry(
                    interview: interview,
                    unit: unit,
                    text: segments.map(\.text).joined(separator: " "),
                    speaker: segments.first?.speaker ?? "—",
                    time: Self.timeRange(segments),
                    themePaths: unit.themeIDs.map(store.themePathName).sorted()
                )
            }
        }
    }

    private var entries: [QuoteEntry] {
        allEntries.filter { entry in
            let searchable = ([entry.text, entry.speaker, entry.interview.participant, entry.unit.memo] + entry.themePaths).joined(separator: " ")
            let matchesQuery = query.isEmpty || searchable.localizedCaseInsensitiveContains(query)
            let matchesParticipant = participantFilter == nil || entry.interview.id == participantFilter
            let matchesSpeaker = speakerFilter == nil || entry.speaker == speakerFilter
            let matchesTheme = selectedThemeFilter == nil || entry.unit.themeIDs.contains { assignedID in
                includeDescendants ? store.theme(assignedID, isDescendantOf: selectedThemeFilter!) : assignedID == selectedThemeFilter
            }
            return matchesQuery && matchesParticipant && matchesSpeaker && matchesTheme
        }
    }

    private var availableSpeakers: [String] {
        Array(Set(allEntries.map(\.speaker).filter { !$0.isEmpty && $0 != "—" }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var hasActiveFilters: Bool {
        !query.isEmpty || participantFilter != nil || speakerFilter != nil || selectedThemeFilter != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Coded Excerpts").font(.title2).fontWeight(.semibold)
                    if hasActiveFilters {
                        (Text(entries.count.formatted()) + Text(" / ") + Text(allEntries.count.formatted()) + Text(" results shown"))
                            .foregroundStyle(.secondary)
                    } else {
                        (Text(allEntries.count.formatted()) + Text(" coded excerpt(s)"))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button("Filtered Table (CSV)") { exportFiltered() }
                    Button("Full Project Archive (ZIP)") { exportProject() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }.padding(16)

            filterBar
            Divider()

            Table(entries) {
                TableColumn("Participant") { entry in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(ParticipantPalette.color(ParticipantPalette.index(for: entry.interview.id, in: store.project.interviews)))
                            .frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.interview.participant).fontWeight(.medium)
                            Text(entry.speaker).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.width(min: 110, ideal: 150)
                TableColumn("Time") { entry in Text(entry.time).monospacedDigit() }
                    .width(min: 80, ideal: 100)
                TableColumn("Excerpt") { entry in
                    Text(entry.text).lineLimit(4).textSelection(.enabled)
                }.width(min: 280, ideal: 480)
                TableColumn("Theme Path") { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(entry.themePaths, id: \.self) { path in
                            Text(path).font(.caption).lineLimit(2)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }.width(min: 190, ideal: 280)
                TableColumn("Note") { entry in Text(entry.unit.memo).lineLimit(3).foregroundStyle(.secondary) }
                    .width(min: 120, ideal: 180)
                TableColumn("") { entry in
                    Button(role: .destructive) {
                        store.removeCodingUnit(entry.unit.id, interviewID: entry.interview.id)
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).help("Remove coding")
                }.width(28)
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No matching excerpts",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Clear the filters or create a new coding.")
                    )
                }
            }
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Label("Filters", systemImage: "line.3.horizontal.decrease")
                    .font(.callout).fontWeight(.semibold)
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search excerpt, speaker, theme, or note", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 9).frame(minWidth: 280, maxWidth: 520, minHeight: 30)
                .background(.background, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator))
                Spacer()
                if hasActiveFilters {
                    Button("Clear All", systemImage: "xmark.circle") { clearFilters() }
                        .controlSize(.small)
                }
            }

            HStack(spacing: 10) {
                Picker("Participant", selection: $participantFilter) {
                    Text("All participants").tag(Optional<UUID>.none)
                    ForEach(store.project.interviews) { Text($0.participant).tag(Optional($0.id)) }
                }
                .frame(width: 220)

                Picker("Speaker", selection: $speakerFilter) {
                    Text("All speakers").tag(Optional<String>.none)
                    ForEach(availableSpeakers, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .frame(width: 220)

                ThemeHierarchyPickerButton(
                    store: store,
                    title: selectedThemeFilter.map { store.themeName($0) } ?? AppLocalization.string("Choose Theme…"),
                    prominent: false
                ) { selectedThemeFilter = $0 }

                Toggle("Include subthemes", isOn: $includeDescendants)
                    .toggleStyle(.checkbox)
                    .disabled(selectedThemeFilter == nil)

                if selectedThemeFilter != nil {
                    Button { selectedThemeFilter = nil } label: { Label("Remove theme filter", systemImage: "xmark") }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .help("Remove theme filter")
                }
                Spacer()
            }

            if hasActiveFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        Text("Active").font(.caption).foregroundStyle(.secondary)
                        if let participantFilter,
                           let interview = store.project.interviews.first(where: { $0.id == participantFilter }) {
                            FilterToken(title: interview.participant, symbol: "person", remove: { self.participantFilter = nil })
                        }
                        if let speakerFilter {
                            FilterToken(title: speakerFilter, symbol: "waveform", remove: { self.speakerFilter = nil })
                        }
                        if let selectedThemeFilter {
                            FilterToken(title: store.themePathName(for: selectedThemeFilter), symbol: "tag", remove: { self.selectedThemeFilter = nil })
                        }
                        if !query.isEmpty {
                            FilterToken(title: "“\(query)”", symbol: "magnifyingglass", remove: { query = "" })
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
    }

    private func clearFilters() {
        query = ""
        participantFilter = nil
        speakerFilter = nil
        selectedThemeFilter = nil
        includeDescendants = true
    }

    private func exportFiltered() {
        do {
            let rows = entries.map {
                QuoteExportRow(
                    participant: $0.interview.participant,
                    interview: $0.interview.name,
                    speaker: $0.speaker,
                    time: $0.time,
                    text: $0.text,
                    themes: $0.themePaths.joined(separator: " | "),
                    memo: $0.unit.memo
                )
            }
            if let url = try ExportService.exportQuotes(rows) { store.lastMessage = "Table exported: \(url.lastPathComponent)" }
        } catch { store.lastMessage = "Export failed: \(error.localizedDescription)" }
    }

    private func exportProject() {
        do {
            if let url = try ExportService.exportProjectArchive(store: store) { store.lastMessage = "Project archive created: \(url.lastPathComponent)" }
        } catch { store.lastMessage = "Could not create archive: \(error.localizedDescription)" }
    }

    private static func timeRange(_ segments: [TranscriptSegment]) -> String {
        guard let first = segments.first else { return "—" }
        let end = segments.last?.end ?? first.end
        return first.start.isEmpty ? "—" : "\(first.start)–\(end)"
    }
}

private struct FilterToken: View {
    let title: String
    let symbol: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(title).lineLimit(1)
            Button(action: remove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .accessibilityLabel("\(AppLocalization.string("Remove filter")): \(title)")
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.tint.opacity(0.10), in: Capsule())
    }
}

private struct QuoteEntry: Identifiable {
    var id: UUID { unit.id }
    let interview: Interview
    let unit: CodingUnit
    let text: String
    let speaker: String
    let time: String
    let themePaths: [String]
}

struct FlowTags: View {
    let names: [String]
    var body: some View {
        HStack(spacing: 5) {
            ForEach(names, id: \.self) { name in
                Text(name).font(.caption2).lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.tint.opacity(0.12), in: Capsule())
            }
        }
    }
}
