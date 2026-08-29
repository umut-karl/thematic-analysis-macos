import SwiftUI

struct TranscriptTableView: View {
    @ObservedObject var store: AnalysisStore
    let codingMode: Bool
    @State private var query = ""
    @State private var codedOnly = false
    @State private var isEditingTable = false
    @State private var showDeleteConfirmation = false
    @AppStorage("transcriptNumberColumnWidth") private var numberColumnWidth = 32.0
    @AppStorage("transcriptSpeakerColumnWidth") private var speakerColumnWidth = 90.0
    @AppStorage("transcriptTimeColumnWidth") private var timeColumnWidth = 108.0

    private var rows: [TranscriptSegment] {
        guard let interview = store.selectedInterview else { return [] }
        return interview.segments.filter { segment in
            let matchesQuery = query.isEmpty || segment.text.localizedCaseInsensitiveContains(query)
                || segment.speaker.localizedCaseInsensitiveContains(query)
            let matchesCoding = !codedOnly || store.codingUnit(containing: segment.id) != nil
            return matchesQuery && matchesCoding
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let interview = store.selectedInterview {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(interview.name).font(.title2).fontWeight(.semibold)
                        Text(interview.segments.count.formatted()) + Text(" row(s) · ")
                            + Text(interview.codingUnits.count.formatted()) + Text(" coding unit(s)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Coded only", isOn: $codedOnly).toggleStyle(.switch)
                    Button {
                        exportTranscript(interview)
                    } label: {
                        Label("Excel", systemImage: "square.and.arrow.up")
                    }
                    .help("Export this transcript to Excel with speaker and time information")
                    if !codingMode {
                        Divider().frame(height: 22)
                        if isEditingTable {
                            Button { store.insertTranscriptRow() } label: { Label("Add Row", systemImage: "plus") }
                            Button { store.mergeSelectedTranscriptRows() } label: { Label("Merge", systemImage: "arrow.triangle.merge") }
                                .disabled(store.selectedSegmentIDs.count < 2)
                                .help("Merge selected rows while preserving text and time range")
                            Button(role: .destructive) { showDeleteConfirmation = true } label: { Label("Delete", systemImage: "trash") }
                                .disabled(store.selectedSegmentIDs.isEmpty)
                        }
                        Button(isEditingTable ? "Done" : "Edit Table") {
                            isEditingTable.toggle()
                            if !isEditingTable { store.persist() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
            }

            TranscriptGrid(
                rows: rows,
                store: store,
                isEditing: isEditingTable,
                numberColumnWidth: $numberColumnWidth,
                speakerColumnWidth: $speakerColumnWidth,
                timeColumnWidth: $timeColumnWidth,
                binding: binding
            )
            .searchable(text: $query, prompt: "Search text or speaker")
            .overlay {
                if rows.isEmpty { ContentUnavailableView("No rows found", systemImage: "text.magnifyingglass") }
            }

            if codingMode {
                HStack {
                    if store.selectedSegmentIDs.isEmpty {
                        Text("Select one or several consecutive rows to code.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        (Text(store.selectedSegmentIDs.count.formatted()) + Text(" row(s) selected"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !store.selectedSegmentIDs.isEmpty {
                        Text("Select multiple rows using checkboxes").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 16).frame(height: 38).background(.bar)
            }
        }
        .alert("Delete selected rows?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Rows", role: .destructive) { store.deleteSelectedTranscriptRows() }
        } message: {
            Text("Coding linked to these rows will be updated and the project will be saved automatically.")
        }
    }

    private func binding(_ id: UUID, _ keyPath: WritableKeyPath<TranscriptSegment, String>) -> Binding<String> {
        Binding(
            get: { store.segment(id)?[keyPath: keyPath] ?? "" },
            set: { newValue in store.updateSegment(id) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func exportTranscript(_ interview: Interview) {
        do {
            if let url = try ExportService.exportTranscriptXLSX(interview) {
                store.lastMessage = "Excel export saved: \(url.lastPathComponent)"
            }
        } catch {
            store.lastMessage = "Could not create Excel export: \(error.localizedDescription)"
        }
    }
}

private struct TranscriptGrid: View {
    let rows: [TranscriptSegment]
    @ObservedObject var store: AnalysisStore
    let isEditing: Bool
    @Binding var numberColumnWidth: Double
    @Binding var speakerColumnWidth: Double
    @Binding var timeColumnWidth: Double
    let binding: (UUID, WritableKeyPath<TranscriptSegment, String>) -> Binding<String>

    private var speakerIndices: [String: Int] {
        let source = store.selectedInterview?.segments.sorted { $0.order < $1.order } ?? rows
        return SpeakerPalette.indices(for: source.map(\.speaker))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(rows) { row in
                        TranscriptGridRow(
                            row: row,
                            store: store,
                            isEditing: isEditing,
                            numberColumnWidth: numberColumnWidth,
                            speakerColumnWidth: speakerColumnWidth,
                            timeColumnWidth: timeColumnWidth,
                            speakerColorIndex: SpeakerPalette.index(for: row.speaker, in: speakerIndices),
                            binding: binding
                        )
                        Divider().padding(.leading, 38)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 22)
                        ResizableColumnHeader("#", width: $numberColumnWidth, range: 28...72)
                        ResizableColumnHeader("Speaker", width: $speakerColumnWidth, range: 70...240)
                        ResizableColumnHeader("Time", width: $timeColumnWidth, range: 100...220)
                        Text("Text").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 7).background(.bar)
                }
            }
        }
    }
}

private struct TranscriptGridRow: View {
    let row: TranscriptSegment
    @ObservedObject var store: AnalysisStore
    let isEditing: Bool
    let numberColumnWidth: Double
    let speakerColumnWidth: Double
    let timeColumnWidth: Double
    let speakerColorIndex: Int?
    let binding: (UUID, WritableKeyPath<TranscriptSegment, String>) -> Binding<String>
    @Environment(\.colorScheme) private var colorScheme

    private var isSelected: Bool { store.selectedSegmentIDs.contains(row.id) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { toggleSelection() } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain).frame(width: 22)
            .help(AppLocalization.string(isSelected ? "Deselect row" : "Select row"))

            Text(row.order.formatted()).font(.caption).foregroundStyle(.secondary)
                .frame(width: numberColumnWidth, alignment: .leading).padding(.top, 4)

            if isEditing {
                TextField("Speaker", text: binding(row.id, \.speaker), axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...3).frame(width: speakerColumnWidth)
                HStack(spacing: 3) {
                    TextField("00:00", text: binding(row.id, \.start)).textFieldStyle(.roundedBorder).frame(width: 48)
                    Text("–").foregroundStyle(.tertiary)
                    TextField("00:00", text: binding(row.id, \.end)).textFieldStyle(.roundedBorder).frame(width: 48)
                }.font(.caption).monospacedDigit().frame(width: timeColumnWidth)
                TextField("Transcript text", text: binding(row.id, \.text), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .lineLimit(2...10)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 6) {
                    if let speakerColorIndex {
                        Circle().fill(SpeakerPalette.color(speakerColorIndex)).frame(width: 8, height: 8)
                    }
                    Text(row.speaker.isEmpty ? "—" : row.speaker)
                        .font(.callout).fontWeight(.medium).lineLimit(3)
                }
                .frame(width: speakerColumnWidth, alignment: .leading).padding(.top, 2)
                Text(row.start.isEmpty ? "—" : "\(row.start)–\(row.end)")
                    .font(.callout).monospacedDigit().frame(width: timeColumnWidth, alignment: .leading).padding(.top, 2)
                HStack(alignment: .top, spacing: 8) {
                    Text(row.text.isEmpty ? "Empty row" : row.text)
                        .font(.callout)
                        .foregroundStyle(row.text.isEmpty ? .secondary : .primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let unit = store.codingUnit(containing: row.id) {
                        Text("\(unit.themeIDs.count)")
                            .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.tint.opacity(0.14), in: Capsule())
                            .help(unit.themeIDs.map(store.themeName).joined(separator: ", "))
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if let speakerColorIndex {
                Rectangle().fill(SpeakerPalette.color(speakerColorIndex)).frame(width: 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing { toggleSelection() }
        }
    }

    private func toggleSelection() {
        if isSelected { store.selectedSegmentIDs.remove(row.id) }
        else { store.selectedSegmentIDs.insert(row.id) }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.14) }
        if let speakerColorIndex {
            return SpeakerPalette.color(speakerColorIndex).opacity(colorScheme == .dark ? 0.17 : 0.08)
        }
        return row.order.isMultiple(of: 2) ? Color.secondary.opacity(0.035) : Color.clear
    }
}

private struct ResizableColumnHeader: View {
    let title: String
    @Binding var width: Double
    let range: ClosedRange<Double>
    @State private var dragOrigin: Double?
    @State private var isHovering = false

    init(_ title: String, width: Binding<Double>, range: ClosedRange<Double>) {
        self.title = title
        self._width = width
        self.range = range
    }

    var body: some View {
        Text(LocalizedStringKey(title))
            .frame(width: width, alignment: .leading)
            .overlay(alignment: .trailing) {
                ZStack {
                    Rectangle()
                        .fill(isHovering ? Color.accentColor : Color.secondary.opacity(0.28))
                        .frame(width: isHovering ? 2 : 1)
                    Color.clear.frame(width: 10)
                }
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovering = hovering
                    if hovering { NSCursor.resizeLeftRight.push() }
                    else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragOrigin == nil { dragOrigin = width }
                            width = clamped((dragOrigin ?? width) + value.translation.width)
                        }
                        .onEnded { _ in dragOrigin = nil }
                )
                .help("\(AppLocalization.string(title)) · \(AppLocalization.string("Change column width"))")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(AppLocalization.string(title)) · \(AppLocalization.string("Column width"))")
            .accessibilityValue("\(Int(width)) punto")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: width = clamped(width + 10)
                case .decrement: width = clamped(width - 10)
                @unknown default: break
                }
            }
    }

    private func clamped(_ proposed: Double) -> Double {
        min(max(proposed, range.lowerBound), range.upperBound)
    }
}
