import SwiftUI

struct DebugFrameworkMatrixView: View {
    let dataset: DebugResearchDataset
    @Bindable var workspace: DebugFrameworkMatrixWorkspace

    @State private var displayMode: FrameworkDisplayMode = .visual
    @State private var caseSort: FrameworkCaseSort = .sourceOrder
    @State private var usageGroup: String?
    @State private var selectedCell: FrameworkCellSelection
    @State private var isInspectorPresented = false
    @State private var isColumnPickerPresented = false

    private let participantWidth: CGFloat = 168
    private let summaryThemeWidth: CGFloat = 204
    private let visualThemeWidth: CGFloat = 122

    init(dataset: DebugResearchDataset, workspace: DebugFrameworkMatrixWorkspace) {
        self.dataset = dataset
        self.workspace = workspace
        let participantID = dataset.participants.first?.id ?? ""
        let columnID = workspace.columns.first?.id ?? ""
        _selectedCell = State(initialValue: FrameworkCellSelection(participantID: participantID, columnID: columnID))
    }

    private var usageGroups: [String] {
        Array(Set(dataset.participants.map(\.usageGroup))).sorted()
    }

    private var visibleColumns: [FrameworkMatrixColumn] {
        workspace.columns.filter { workspace.visibleColumnIDs.contains($0.id) }
    }

    private var participants: [DebugResearchParticipant] {
        let filtered = dataset.participants.filter { usageGroup == nil || $0.usageGroup == usageGroup }
        switch caseSort {
        case .sourceOrder:
            return filtered
        case .evidenceDensity:
            return filtered.sorted { totalEvidence(for: $0) > totalEvidence(for: $1) }
        case .pattern:
            return filtered.sorted {
                let left = patternKey(for: $0)
                let right = patternKey(for: $1)
                return left == right ? totalEvidence(for: $0) > totalEvidence(for: $1) : left > right
            }
        }
    }

    private var selectedParticipant: DebugResearchParticipant? {
        dataset.participant(selectedCell.participantID)
    }

    private var selectedColumn: FrameworkMatrixColumn? {
        workspace.columns.first { $0.id == selectedCell.columnID }
    }

    private var maximumEvidenceCount: Int {
        max(participants.flatMap { participant in
            visibleColumns.map { evidence(for: $0, participantID: participant.id).count }
        }.max() ?? 1, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            matrix
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inspector(isPresented: $isInspectorPresented) {
            inspector
                .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
        }
        .onChange(of: usageGroup) { _, _ in keepParticipantSelectionVisible() }
        .onChange(of: workspace.visibleColumnIDs) { _, _ in keepColumnSelectionVisible() }
        .onChange(of: workspace.columns) { _, _ in keepColumnSelectionVisible() }
    }

    @ViewBuilder
    private var inspector: some View {
        if let participant = selectedParticipant, let column = selectedColumn {
            FrameworkEvidenceInspector(
                participant: participant,
                column: column,
                summary: summaryBinding(participantID: participant.id, columnID: column.id),
                linkedExcerptIDs: linkedExcerptIDsBinding(participantID: participant.id, columnID: column.id),
                cellExcerpts: evidence(for: column, participantID: participant.id),
                caseExcerpts: dataset.excerpts.filter { $0.participantID == participant.id },
                dataset: dataset,
                isPresented: $isInspectorPresented
            )
        } else {
            ContentUnavailableView("No cell selected", systemImage: "tablecells")
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker("View", selection: $displayMode) {
                ForEach(FrameworkDisplayMode.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 176)
            .accessibilityLabel("Matrix view")

            Divider().frame(height: 20)
            participantMenu
            sortMenu
            Divider().frame(height: 20)
            columnsButton
            Spacer(minLength: 8)

            Text("\(participants.count) × \(visibleColumns.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .help("Number of visible participants and columns")

            Button {
                isInspectorPresented.toggle()
            } label: {
                Label("Details", systemImage: "sidebar.trailing")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(isInspectorPresented ? "Hide details" : "Show details")
            .accessibilityLabel(isInspectorPresented ? "Hide details" : "Show details")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var participantMenu: some View {
        Menu {
            Button {
                usageGroup = nil
            } label: {
                Label("All participants", systemImage: usageGroup == nil ? "checkmark" : "person.2")
            }
            Divider()
            ForEach(usageGroups, id: \.self) { group in
                Button {
                    usageGroup = group
                } label: {
                    Label(group, systemImage: usageGroup == group ? "checkmark" : "person")
                }
            }
        } label: {
            Label(usageGroup ?? "All participants", systemImage: "person.2")
                .lineLimit(1)
        }
        .help("Filter participant group")
    }

    private var sortMenu: some View {
        Menu {
            ForEach(FrameworkCaseSort.allCases) { sort in
                Button {
                    caseSort = sort
                } label: {
                    Label { Text(LocalizedStringKey(sort.rawValue)) } icon: {
                        Image(systemName: caseSort == sort ? "checkmark" : "arrow.up.arrow.down")
                    }
                }
            }
        } label: {
            Label { Text(LocalizedStringKey(caseSort.rawValue)) } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
        .help("Sort participants")
    }

    private var columnsButton: some View {
        Button {
            isColumnPickerPresented.toggle()
        } label: {
            Label("Columns (\(visibleColumns.count))", systemImage: "rectangle.split.3x1")
        }
        .popover(isPresented: $isColumnPickerPresented, arrowEdge: .bottom) {
            FrameworkColumnPicker(
                workspace: workspace,
                isPresented: $isColumnPickerPresented
            )
        }
        .help("Add and manage columns")
    }

    private var matrix: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(participants.enumerated()), id: \.element.id) { row, participant in
                        HStack(spacing: 0) {
                            participantHeader(participant)
                            ForEach(visibleColumns) { column in
                                matrixCell(participant: participant, column: column)
                            }
                        }
                        .background(row.isMultiple(of: 2) ? Color.secondary.opacity(0.035) : .clear)
                        Divider()
                    }
                } header: {
                    matrixHeader
                    Divider()
                }
            }
            .frame(minWidth: matrixWidth, alignment: .topLeading)
        }
        // LazyVStack's pinned header can retain its old vertical anchor while
        // the two modes animate between different row/column dimensions.
        // Rebuilding only the scroll surface keeps the header at the origin
        // without disturbing the selected cell or inspector state.
        .id(displayMode)
        .background(.background)
    }

    @ViewBuilder
    private func matrixCell(participant: DebugResearchParticipant, column: FrameworkMatrixColumn) -> some View {
        let excerpts = evidence(for: column, participantID: participant.id)
        let count = excerpts.count
        let summary = column.summaries[participant.id] ?? ""
        let selected = selectedCell.participantID == participant.id && selectedCell.columnID == column.id

        if displayMode == .summary {
            FrameworkSummaryCell(
                summary: summary,
                evidenceCount: count,
                tint: ThemePalette.color(column.colorIndex),
                isSelected: selected
            ) { select(participant, column) }
            .frame(width: summaryThemeWidth, height: 92)
        } else {
            FrameworkVisualCell(
                evidenceCount: count,
                maximumCount: maximumEvidenceCount,
                summary: summary,
                tint: ThemePalette.color(column.colorIndex),
                isSelected: selected
            ) { select(participant, column) }
            .frame(width: visualThemeWidth, height: 62)
        }
    }

    private var matrixHeader: some View {
        HStack(spacing: 0) {
            Text("Participant")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(width: participantWidth, alignment: .leading)
                .frame(minHeight: 48)

            ForEach(visibleColumns) { column in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(ThemePalette.color(column.colorIndex))
                        .frame(width: 7, height: 7)
                        .padding(.top, 4)
                    Text(column.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 8)
                .frame(width: columnWidth, alignment: .leading)
                .frame(minHeight: 48)
                .overlay(alignment: .leading) { Divider() }
                .help("\(column.title) · \(column.kindLabel)")
            }
        }
        .background(.bar)
    }

    private func participantHeader(_ participant: DebugResearchParticipant) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(participant.name).fontWeight(.semibold).lineLimit(1)
            Text(participant.role).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(width: participantWidth, height: rowHeight, alignment: .leading)
    }

    private var columnWidth: CGFloat {
        displayMode == .summary ? summaryThemeWidth : visualThemeWidth
    }

    private var rowHeight: CGFloat {
        displayMode == .summary ? 92 : 62
    }

    private var matrixWidth: CGFloat {
        participantWidth + CGFloat(visibleColumns.count) * columnWidth
    }

    private func evidence(for column: FrameworkMatrixColumn, participantID: String) -> [DebugResearchExcerpt] {
        switch column.source {
        case let .candidateTheme(id):
            guard let theme = dataset.candidateThemes.first(where: { $0.id == id }) else { return [] }
            return dataset.excerpts(for: theme, participantID: participantID)
        case let .code(id):
            return dataset.excerpts.filter { $0.participantID == participantID && $0.codeIDs.contains(id) }
        case .custom:
            return []
        }
    }

    private func totalEvidence(for participant: DebugResearchParticipant) -> Int {
        visibleColumns.reduce(0) { $0 + evidence(for: $1, participantID: participant.id).count }
    }

    private func patternKey(for participant: DebugResearchParticipant) -> String {
        visibleColumns.map { evidence(for: $0, participantID: participant.id).isEmpty ? "0" : "1" }.joined()
    }

    private func summaryBinding(participantID: String, columnID: String) -> Binding<String> {
        Binding(
            get: {
                workspace.columns.first(where: { $0.id == columnID })?.summaries[participantID] ?? ""
            },
            set: { newValue in
                guard let index = workspace.columns.firstIndex(where: { $0.id == columnID }) else { return }
                workspace.columns[index].summaries[participantID] = newValue
            }
        )
    }

    private func linkedExcerptIDsBinding(participantID: String, columnID: String) -> Binding<Set<String>> {
        Binding(
            get: {
                workspace.linkedExcerptIDs(participantID: participantID, columnID: columnID)
            },
            set: { ids in
                workspace.setLinkedExcerptIDs(ids, participantID: participantID, columnID: columnID)
            }
        )
    }

    private func select(_ participant: DebugResearchParticipant, _ column: FrameworkMatrixColumn) {
        selectedCell = FrameworkCellSelection(participantID: participant.id, columnID: column.id)
        isInspectorPresented = true
    }

    private func keepParticipantSelectionVisible() {
        if !participants.contains(where: { $0.id == selectedCell.participantID }), let first = participants.first {
            selectedCell = FrameworkCellSelection(participantID: first.id, columnID: selectedCell.columnID)
        }
    }

    private func keepColumnSelectionVisible() {
        if !workspace.visibleColumnIDs.contains(selectedCell.columnID), let first = visibleColumns.first {
            selectedCell = FrameworkCellSelection(participantID: selectedCell.participantID, columnID: first.id)
        }
    }
}

private enum FrameworkDisplayMode: String, CaseIterable, Identifiable {
    case visual = "Density"
    case summary = "Summary"
    var id: String { rawValue }
}

private enum FrameworkCaseSort: String, CaseIterable, Identifiable {
    case sourceOrder = "Source Order"
    case evidenceDensity = "Evidence Density"
    case pattern = "Pattern Similarity"
    var id: String { rawValue }
}

private struct FrameworkCellSelection: Hashable {
    let participantID: String
    let columnID: String
}

private struct FrameworkSummaryCell: View {
    let summary: String
    let evidenceCount: Int
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                if summary.isEmpty {
                    Text("Add summary…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                } else {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if evidenceCount > 0 {
                        Label(evidenceCount.formatted(), systemImage: "quote.bubble")
                    }
                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .opacity(isSelected || summary.isEmpty ? 1 : 0)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
            .background(isSelected ? tint.opacity(0.13) : .clear)
            .overlay(alignment: .leading) { Divider() }
            .overlay(Rectangle().stroke(isSelected ? tint : .clear, lineWidth: 2).padding(2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open summary and evidence")
        .accessibilityLabel(
            "\(summary.isEmpty ? "No summary" : summary), \(evidenceCount) excerpts"
        )
    }
}

private struct FrameworkVisualCell: View {
    let evidenceCount: Int
    let maximumCount: Int
    let summary: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    private var intensity: Double {
        guard evidenceCount > 0 else { return 0 }
        return Double(evidenceCount) / Double(max(maximumCount, 1))
    }

    private var symbolSize: CGFloat { 16 + CGFloat(intensity) * 20 }

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(evidenceCount == 0 ? Color.secondary.opacity(0.018) : tint.opacity(0.07 + intensity * 0.23))
                if evidenceCount == 0 {
                    Circle().stroke(.tertiary, lineWidth: 1).frame(width: 8, height: 8)
                } else {
                    Circle().fill(tint.gradient).frame(width: symbolSize, height: symbolSize)
                    Text(evidenceCount.formatted())
                        .font(.caption2).fontWeight(.bold).foregroundStyle(.white).monospacedDigit()
                }
            }
            .overlay(alignment: .leading) { Divider() }
            .overlay(Rectangle().stroke(isSelected ? tint : .clear, lineWidth: 2).padding(2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(summary.isEmpty ? "No summary" : summary) · \(evidenceCount) excerpts")
        .accessibilityLabel("\(summary.isEmpty ? "No summary" : summary), \(evidenceCount) excerpts")
    }
}

private struct FrameworkColumnPicker: View {
    @Bindable var workspace: DebugFrameworkMatrixWorkspace
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var newColumnName = ""

    private var filteredColumns: [FrameworkMatrixColumn] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return workspace.columns }
        return workspace.columns.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var canAddColumn: Bool {
        let trimmed = newColumnName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !workspace.columns.contains {
            $0.title.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Columns").font(.headline)
                Spacer()
                Text("\(workspace.visibleColumnIDs.count)/\(workspace.columns.count)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Button { isPresented = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Close")
            }
            .padding(12)

            HStack(spacing: 6) {
                TextField("New column", text: $newColumnName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addColumn)
                Button(action: addColumn) {
                    Label("Add", systemImage: "plus")
                }
                .disabled(!canAddColumn)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            TextField("Search themes or codes", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredColumns) { column in
                        columnRow(column)
                    }

                    if filteredColumns.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .frame(maxWidth: .infinity, minHeight: 150)
                    }
                }
            }

            Divider()

            HStack {
                Button("Show All") {
                    workspace.visibleColumnIDs = Set(workspace.columns.map(\.id))
                }
                .disabled(workspace.visibleColumnIDs.count == workspace.columns.count)
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 380, height: 470)
    }

    private func columnRow(_ column: FrameworkMatrixColumn) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: visibilityBinding(for: column.id)) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(workspace.visibleColumnIDs.count == 1 && workspace.visibleColumnIDs.contains(column.id))

            Circle()
                .fill(ThemePalette.color(column.colorIndex))
                .frame(width: 7, height: 7)

            if column.isCustom {
                TextField("Column name", text: titleBinding(for: column.id))
                    .textFieldStyle(.plain)
            } else {
                Text(column.title).lineLimit(1)
            }

            Spacer(minLength: 4)
            Text(column.kindLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if column.isCustom {
                Button {
                    workspace.deleteCustomColumn(column.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete column")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func addColumn() {
        guard canAddColumn else { return }
        workspace.addCustomColumn(named: newColumnName)
        newColumnName = ""
    }

    private func visibilityBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { workspace.visibleColumnIDs.contains(id) },
            set: { isVisible in
                if isVisible {
                    workspace.visibleColumnIDs.insert(id)
                } else if workspace.visibleColumnIDs.count > 1 {
                    workspace.visibleColumnIDs.remove(id)
                }
            }
        )
    }

    private func titleBinding(for id: String) -> Binding<String> {
        Binding(
            get: { workspace.columns.first(where: { $0.id == id })?.title ?? "" },
            set: { value in
                guard let index = workspace.columns.firstIndex(where: { $0.id == id }) else { return }
                workspace.columns[index].title = value
            }
        )
    }
}

private struct FrameworkEvidenceInspector: View {
    let participant: DebugResearchParticipant
    let column: FrameworkMatrixColumn
    @Binding var summary: String
    @Binding var linkedExcerptIDs: Set<String>
    let cellExcerpts: [DebugResearchExcerpt]
    let caseExcerpts: [DebugResearchExcerpt]
    let dataset: DebugResearchDataset
    @Binding var isPresented: Bool

    @State private var scope: FrameworkEvidenceScope = .cell

    private var displayedExcerpts: [DebugResearchExcerpt] {
        switch scope {
        case .cell: cellExcerpts
        case .caseContext: caseExcerpts
        case .summaryLinks: caseExcerpts.filter { linkedExcerptIDs.contains($0.id) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(participant.name).font(.headline)
                    Text(column.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button { isPresented = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Close details")
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Summary")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    TextField("Write this participant's theme summary", text: $summary, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(4...9)

                    Picker("Evidence", selection: $scope) {
                        ForEach(FrameworkEvidenceScope.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if displayedExcerpts.isEmpty {
                        ContentUnavailableView(scope.emptyMessage, systemImage: "quote.bubble")
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        ForEach(displayedExcerpts) { excerpt in
                            VStack(alignment: .trailing, spacing: 5) {
                                DebugExcerptCard(
                                    excerpt: excerpt,
                                    dataset: dataset,
                                    emphasized: linkedExcerptIDs.contains(excerpt.id)
                                )

                                Button {
                                    toggleSummaryLink(excerpt.id)
                                } label: {
                                    Label(
                                        linkedExcerptIDs.contains(excerpt.id) ? "Unlink" : "Link to Summary",
                                        systemImage: linkedExcerptIDs.contains(excerpt.id) ? "link.badge.minus" : "link.badge.plus"
                                    )
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .id("\(participant.id)-\(column.id)")
    }

    private func toggleSummaryLink(_ excerptID: String) {
        if linkedExcerptIDs.contains(excerptID) {
            linkedExcerptIDs.remove(excerptID)
        } else {
            linkedExcerptIDs.insert(excerptID)
        }
    }
}

private enum FrameworkEvidenceScope: String, CaseIterable, Identifiable {
    case cell = "Cell"
    case caseContext = "Full Case"
    case summaryLinks = "Linked to Summary"
    var id: String { rawValue }

    var emptyMessage: String {
        switch self {
        case .cell: "No evidence in this cell"
        case .caseContext: "No evidence in this case"
        case .summaryLinks: "No evidence linked to the summary"
        }
    }
}
