import SwiftUI
import Observation

struct ThemeMapView: View {
    @ObservedObject var store: AnalysisStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewportState = ThemeMapViewportState()
    @State private var query = ""
    @State private var selectedThemeID: UUID?
    @State private var collapsedThemeIDs: Set<UUID> = []
    @State private var viewportResetToken = 0

    private var layout: ThemeLayout { ThemeLayout(themes: store.project.themes, collapsed: collapsedThemeIDs) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tema Haritası").font(.title2).fontWeight(.semibold)
                    (Text(store.project.themes.count.formatted()) + Text(" düğüm · sınırsız hiyerarşi")).foregroundStyle(.secondary)
                }
                Spacer()
                ThemeMapZoomControls(viewportState: viewportState)
                Menu {
                    Button("Tüm Dalları Aç") {
                        updateAllBranchesAndFit { collapsedThemeIDs.removeAll() }
                    }
                    Button("Tüm Dalları Daralt") {
                        updateAllBranchesAndFit {
                            collapsedThemeIDs = Set(store.project.themes.filter { !store.children(of: $0.id).isEmpty }.map(\.id))
                        }
                    }
                } label: { Label("Dallar", systemImage: "arrow.down.right.and.arrow.up.left") }
                Button("Sığdır") { viewportResetToken += 1 }
            }.padding(16)

            ThemeMapViewport(
                store: store,
                layout: layout,
                query: query,
                selectedThemeID: $selectedThemeID,
                collapsedThemeIDs: $collapsedThemeIDs,
                viewportState: viewportState,
                resetToken: $viewportResetToken
            )
            .searchable(text: $query, prompt: "Haritada tema ara")
        }
        .inspector(isPresented: Binding(
            get: { selectedThemeID != nil },
            set: { if !$0 { selectedThemeID = nil } }
        )) {
            if let selectedThemeID {
                ThemeEvidenceInspector(
                    store: store,
                    themeID: selectedThemeID,
                    close: { self.selectedThemeID = nil }
                )
                    .inspectorColumnWidth(min: 300, ideal: 360, max: 460)
            }
        }
    }

    private func updateBranches(_ update: () -> Void) {
        if reduceMotion { update() }
        else { withAnimation(.spring(response: 0.34, dampingFraction: 0.86), update) }
    }

    private func updateAllBranchesAndFit(_ update: @escaping () -> Void) {
        updateBranches(update)
        Task { @MainActor in
            await Task.yield()
            viewportResetToken += 1
        }
    }
}

private struct ThemeMapZoomControls: View {
    @Bindable var viewportState: ThemeMapViewportState

    var body: some View {
        Image(systemName: "minus.magnifyingglass")
        Slider(value: $viewportState.zoom, in: 0.2...2.2, onEditingChanged: { editing in
            if !editing { viewportState.baseZoom = viewportState.zoom }
        })
        .frame(width: 140)
        Image(systemName: "plus.magnifyingglass")
        Text("\(Int(viewportState.zoom * 100))%")
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 42)
    }
}

@Observable
@MainActor
final class ThemeMapViewportState {
    var zoom: CGFloat = 1
    var baseZoom: CGFloat = 1
    var panOffset: CGSize = .zero
    var basePanOffset: CGSize = .zero
    private(set) var hasInitialFit = false

    func fit(layoutSize: CGSize, in viewport: CGSize) {
        guard layoutSize.width > 0, layoutSize.height > 0 else { return }
        let fitted = min((viewport.width - 70) / layoutSize.width, (viewport.height - 70) / layoutSize.height)
        let targetZoom = min(max(fitted, 0.2), 1.15)
        let targetOffset = CGSize(
            width: (viewport.width - layoutSize.width * targetZoom) / 2,
            height: (viewport.height - layoutSize.height * targetZoom) / 2
        )
        baseZoom = targetZoom
        basePanOffset = targetOffset
        zoom = targetZoom
        panOffset = targetOffset
        hasInitialFit = true
    }

    func preserveCenter(from oldSize: CGSize, to newSize: CGSize) {
        guard hasInitialFit, oldSize.width > 0, oldSize.height > 0 else { return }
        let adjustment = CGSize(
            width: (newSize.width - oldSize.width) / 2,
            height: (newSize.height - oldSize.height) / 2
        )
        panOffset = CGSize(
            width: panOffset.width + adjustment.width,
            height: panOffset.height + adjustment.height
        )
        basePanOffset = CGSize(
            width: basePanOffset.width + adjustment.width,
            height: basePanOffset.height + adjustment.height
        )
    }
}

private struct ThemeMapViewport: View {
    @ObservedObject var store: AnalysisStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let layout: ThemeLayout
    let query: String
    @Binding var selectedThemeID: UUID?
    @Binding var collapsedThemeIDs: Set<UUID>
    @Bindable var viewportState: ThemeMapViewportState
    @Binding var resetToken: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color(nsColor: .textBackgroundColor).opacity(0.45)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedThemeID = nil }

                ThemeMapCanvas(
                    themes: store.project.themes,
                    layout: layout,
                    query: query,
                    selectedThemeID: selectedThemeID,
                    collapsedThemeIDs: collapsedThemeIDs,
                    selectTheme: { selectedThemeID = selectedThemeID == $0 ? nil : $0 },
                    toggleCollapse: toggleCollapse
                )
                .equatable()
                .frame(width: layout.size.width, height: layout.size.height)
                .scaleEffect(viewportState.zoom, anchor: .topLeading)
                .offset(viewportState.panOffset)
                .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: collapsedThemeIDs)
            }
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture(viewportSize: proxy.size))
            .simultaneousGesture(magnificationGesture(viewportSize: proxy.size))
            .onAppear {
                guard !viewportState.hasInitialFit else { return }
                fit(layout: layout, in: proxy.size)
            }
            .onChange(of: resetToken) { fit(layout: layout, in: proxy.size, animated: true) }
            .onChange(of: proxy.size) { oldSize, newSize in
                viewportState.preserveCenter(from: oldSize, to: newSize)
            }
        }
    }

    private func updateBranches(_ update: () -> Void) {
        if reduceMotion { update() }
        else { withAnimation(.spring(response: 0.34, dampingFraction: 0.86), update) }
    }

    private func toggleCollapse(_ themeID: UUID) {
        updateBranches {
            if collapsedThemeIDs.contains(themeID) { collapsedThemeIDs.remove(themeID) }
            else { collapsedThemeIDs.insert(themeID) }
        }
    }

    private func dragGesture(viewportSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    viewportState.panOffset = CGSize(
                        width: viewportState.basePanOffset.width + value.translation.width,
                        height: viewportState.basePanOffset.height + value.translation.height
                    )
                }
            }
            .onEnded { value in
                let current = CGSize(
                    width: viewportState.basePanOffset.width + value.translation.width,
                    height: viewportState.basePanOffset.height + value.translation.height
                )
                guard !reduceMotion else {
                    viewportState.panOffset = current
                    viewportState.basePanOffset = current
                    return
                }

                let prediction = CGSize(
                    width: value.predictedEndTranslation.width - value.translation.width,
                    height: value.predictedEndTranslation.height - value.translation.height
                )
                let momentum = limitedMomentum(prediction)
                let target = constrainedOffset(
                    CGSize(width: current.width + momentum.width, height: current.height + momentum.height),
                    viewportSize: viewportSize
                )
                viewportState.basePanOffset = target
                withAnimation(.timingCurve(0.14, 0.72, 0.16, 1, duration: 0.48)) {
                    viewportState.panOffset = target
                }
            }
    }

    private func magnificationGesture(viewportSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newZoom = min(max(viewportState.baseZoom * value, 0.2), 2.2)
                let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
                let contentX = (center.x - viewportState.basePanOffset.width) / max(viewportState.baseZoom, 0.01)
                let contentY = (center.y - viewportState.basePanOffset.height) / max(viewportState.baseZoom, 0.01)
                viewportState.zoom = newZoom
                viewportState.panOffset = CGSize(width: center.x - contentX * newZoom, height: center.y - contentY * newZoom)
            }
            .onEnded { _ in
                viewportState.baseZoom = viewportState.zoom
                viewportState.basePanOffset = viewportState.panOffset
            }
    }

    private func fit(layout: ThemeLayout, in viewport: CGSize, animated: Bool = false) {
        let update = { viewportState.fit(layoutSize: layout.size, in: viewport) }
        if animated && !reduceMotion {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.88), update)
        } else {
            update()
        }
    }

    private func limitedMomentum(_ prediction: CGSize) -> CGSize {
        let distance = hypot(prediction.width, prediction.height)
        guard distance > 0 else { return .zero }
        let maximumDistance: CGFloat = 260
        let scale = min(0.55, maximumDistance / distance)
        return CGSize(width: prediction.width * scale, height: prediction.height * scale)
    }

    private func constrainedOffset(_ proposed: CGSize, viewportSize: CGSize) -> CGSize {
        let contentSize = CGSize(width: layout.size.width * viewportState.zoom, height: layout.size.height * viewportState.zoom)
        let visibleMargin: CGFloat = 120

        func constrained(_ value: CGFloat, viewport: CGFloat, content: CGFloat) -> CGFloat {
            let lower = min(visibleMargin, viewport - content - visibleMargin)
            let upper = max(visibleMargin, viewport - content + visibleMargin)
            return min(max(value, lower), upper)
        }

        return CGSize(
            width: constrained(proposed.width, viewport: viewportSize.width, content: contentSize.width),
            height: constrained(proposed.height, viewport: viewportSize.height, content: contentSize.height)
        )
    }

}

private struct ThemeMapCanvas: View, Equatable {
    let themes: [ThemeNode]
    let layout: ThemeLayout
    let query: String
    let selectedThemeID: UUID?
    let collapsedThemeIDs: Set<UUID>
    let selectTheme: (UUID) -> Void
    let toggleCollapse: (UUID) -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.layout == rhs.layout
            && lhs.query == rhs.query
            && lhs.selectedThemeID == rhs.selectedThemeID
            && lhs.collapsedThemeIDs == rhs.collapsedThemeIDs
            && lhs.themes.elementsEqual(rhs.themes) { left, right in
                left.id == right.id
                    && left.name == right.name
                    && left.parentID == right.parentID
                    && left.colorIndex == right.colorIndex
            }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.rootIDs, id: \.self) { rootID in
                if let to = layout.positions[rootID] {
                    ThemeConnector(from: layout.centerPosition, to: to, centerNode: true)
                        .stroke(
                            ThemePalette.color(layout.colorIndexes[rootID] ?? 0).opacity(0.68),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            ForEach(layout.edges) { edge in
                if let from = layout.positions[edge.parent], let to = layout.positions[edge.child] {
                    ThemeConnector(from: from, to: to, centerNode: false)
                        .stroke(
                            ThemePalette.color(layout.colorIndexes[edge.child] ?? 0).opacity(0.68),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }

            Text("Temalar")
                .font(.headline)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.5)))
                .position(x: layout.centerPosition.x + 70, y: layout.centerPosition.y + 24)

            ForEach(themes) { theme in
                if let position = layout.positions[theme.id] {
                    ThemeMapNode(
                        theme: theme,
                        highlighted: !query.isEmpty && (
                            theme.name.localizedCaseInsensitiveContains(query)
                                || (layout.pathNames[theme.id] ?? "").localizedCaseInsensitiveContains(query)
                        ),
                        selected: selectedThemeID == theme.id,
                        childCount: layout.childCounts[theme.id] ?? 0,
                        collapsed: collapsedThemeIDs.contains(theme.id),
                        select: { selectTheme(theme.id) },
                        toggleCollapse: { toggleCollapse(theme.id) }
                    )
                    .position(x: position.x + 95, y: position.y + 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
        }
    }
}

private struct ThemeConnector: Shape {
    var from: CGPoint
    var to: CGPoint
    let centerNode: Bool

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(from.x, from.y), AnimatablePair(to.x, to.y)) }
        set {
            from = CGPoint(x: newValue.first.first, y: newValue.first.second)
            to = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        let fromWidth: CGFloat = centerNode ? 140 : 190
        let fromY = from.y + 24
        let toY = to.y + 24
        let goesRight = to.x > from.x
        let startX = goesRight ? from.x + fromWidth : from.x
        let endX = goesRight ? to.x : to.x + 190
        let middle = (startX + endX) / 2
        var path = Path()
        path.move(to: CGPoint(x: startX, y: fromY))
        path.addCurve(
            to: CGPoint(x: endX, y: toY),
            control1: CGPoint(x: middle, y: fromY),
            control2: CGPoint(x: middle, y: toY)
        )
        return path
    }
}

private struct ThemeMapNode: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let theme: ThemeNode
    let highlighted: Bool
    let selected: Bool
    let childCount: Int
    let collapsed: Bool
    let select: () -> Void
    let toggleCollapse: () -> Void
    var body: some View {
        HStack(spacing: 5) {
            Button(action: select) {
                Text(theme.name)
                    .font(.callout).fontWeight(theme.parentID == nil ? .semibold : .regular)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            if childCount > 0 {
                Button(action: toggleCollapse) {
                    Image(systemName: "chevron.right.circle.fill")
                        .foregroundStyle(ThemePalette.color(theme.colorIndex))
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: collapsed)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
                .help(
                    collapsed
                        ? (AppLocalization.language == .english ? "Expand \(childCount) subthemes" : "\(childCount) alt temayı aç")
                        : AppLocalization.string("Alt temaları daralt")
                )
                .accessibilityLabel(AppLocalization.string(collapsed ? "Alt temaları aç" : "Alt temaları daralt"))
                .accessibilityValue(collapsed ? "Kapalı" : "Açık")
            }
        }
        .frame(width: 166).padding(.horizontal, 11).padding(.vertical, 8)
        .background(highlighted ? Color.yellow.opacity(0.35) : ThemePalette.color(theme.colorIndex).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ThemePalette.color(theme.colorIndex), lineWidth: selected ? 3 : (theme.parentID == nil ? 2 : 1)))
        .shadow(color: .black.opacity(selected ? 0.14 : 0.05), radius: selected ? 6 : 3, y: 1)
        .help("Bu temaya bağlı alıntıları göster")
        .accessibilityLabel("\(AppLocalization.string("Tema")): \(theme.name)")
    }
}

private struct ThemeEvidenceInspector: View {
    @ObservedObject var store: AnalysisStore
    let themeID: UUID
    let close: () -> Void

    private var evidence: [ThemeEvidence] {
        store.project.interviews.flatMap { interview in
            interview.codingUnits.compactMap { unit in
                guard unit.themeIDs.contains(where: { store.theme($0, isDescendantOf: themeID) }) else { return nil }
                let segments = interview.segments.filter { unit.segmentIDs.contains($0.id) }.sorted { $0.order < $1.order }
                return ThemeEvidence(
                    id: unit.id,
                    interviewID: interview.id,
                    participant: interview.participant,
                    interview: interview.name,
                    time: segments.first?.start ?? "",
                    text: segments.map(\.text).joined(separator: " "),
                    assignedPaths: unit.themeIDs.filter { store.theme($0, isDescendantOf: themeID) }.map(store.themePathName).sorted()
                )
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.themeName(themeID)).font(.title3).fontWeight(.semibold)
                    Text(store.themePathName(for: themeID)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .padding(6)
                .contentShape(Rectangle())
                .help("Tema ayrıntılarını kapat")
                .accessibilityLabel("Tema ayrıntılarını kapat")
            }
            .padding(16)
            Divider()

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Tema anlatısı", systemImage: "text.alignleft")
                        .font(.callout).fontWeight(.semibold)
                    Spacer()
                    Text("Otomatik kaydedilir").font(.caption2).foregroundStyle(.tertiary)
                }
                ZStack(alignment: .topLeading) {
                    if store.themeNote(themeID).isEmpty {
                        Text("Bu temanın neyi kapsadığını, sınırlarını ve analitik anlamını açıklayın…")
                            .font(.callout).foregroundStyle(.tertiary)
                            .padding(.horizontal, 6).padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: Binding(
                        get: { store.themeNote(themeID) },
                        set: { store.updateThemeNote(themeID, note: $0) }
                    ))
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 92, maxHeight: 150)
                    .padding(3)
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            }
            .padding(14)

            HStack {
                Label("Bağlı alıntılar", systemImage: "text.quote")
                    .font(.callout).fontWeight(.semibold)
                Spacer()
                Text(evidence.count.formatted()).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(.bar)
            Divider()
            if evidence.isEmpty {
                ContentUnavailableView(
                    "Bağlı alıntı yok",
                    systemImage: "text.quote",
                    description: Text("Bu tema veya alt temaları henüz bir ifadeye atanmamış.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(evidence) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Circle()
                                        .fill(ParticipantPalette.color(ParticipantPalette.index(for: item.interviewID, in: store.project.interviews)))
                                        .frame(width: 9, height: 9)
                                    Text(item.participant).font(.caption).fontWeight(.semibold)
                                    Spacer()
                                    Text(item.time).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                }
                                Text(item.text).textSelection(.enabled)
                                ForEach(item.assignedPaths, id: \.self) { path in
                                    Text(path).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Text(item.interview).font(.caption2).foregroundStyle(.tertiary)
                                HStack {
                                    Menu {
                                        ForEach(store.children(of: nil)) { root in
                                            ThemeHierarchyMenuItem(node: root, store: store) { replacementID in
                                                store.replaceThemeAssignments(
                                                    unitID: item.id,
                                                    interviewID: item.interviewID,
                                                    matching: themeID,
                                                    with: replacementID
                                                )
                                            }
                                        }
                                    } label: { Label("Temayı Değiştir", systemImage: "arrow.triangle.2.circlepath") }
                                    .controlSize(.small)
                                    Spacer()
                                    Button(role: .destructive) {
                                        store.removeThemeAssignments(unitID: item.id, interviewID: item.interviewID, matching: themeID)
                                    } label: { Label("Atamayı Kaldır", systemImage: "trash") }
                                    .controlSize(.small)
                                }
                            }
                            .padding(12)
                            .background(
                                ParticipantPalette.color(ParticipantPalette.index(for: item.interviewID, in: store.project.interviews)).opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(ParticipantPalette.color(ParticipantPalette.index(for: item.interviewID, in: store.project.interviews)))
                                    .frame(width: 4).padding(.vertical, 7)
                            }
                        }
                    }.padding(12)
                }
            }
        }
    }
}

private struct ThemeEvidence: Identifiable {
    let id: UUID
    let interviewID: UUID
    let participant: String
    let interview: String
    let time: String
    let text: String
    let assignedPaths: [String]
}

private struct ThemeLayout: Equatable {
    struct Edge: Identifiable, Equatable {
        let parent: UUID
        let child: UUID
        var id: UUID { child }
    }
    var positions: [UUID: CGPoint] = [:]
    var edges: [Edge] = []
    var rootIDs: [UUID] = []
    var childCounts: [UUID: Int] = [:]
    var colorIndexes: [UUID: Int] = [:]
    var pathNames: [UUID: String] = [:]
    var centerPosition: CGPoint = .zero
    var size = CGSize(width: 900, height: 600)

    init(themes: [ThemeNode], collapsed: Set<UUID>) {
        let grouped = Dictionary(grouping: themes, by: \.parentID)
        let themesByID = Dictionary(uniqueKeysWithValues: themes.map { ($0.id, $0) })
        childCounts = Dictionary(uniqueKeysWithValues: themes.map { ($0.id, grouped[$0.id]?.count ?? 0) })
        colorIndexes = Dictionary(uniqueKeysWithValues: themes.map { ($0.id, $0.colorIndex) })

        func pathName(for theme: ThemeNode, visiting: inout Set<UUID>) -> String {
            if let cached = pathNames[theme.id] { return cached }
            guard visiting.insert(theme.id).inserted else { return theme.name }
            defer { visiting.remove(theme.id) }
            let result: String
            if let parentID = theme.parentID, let parent = themesByID[parentID] {
                result = pathName(for: parent, visiting: &visiting) + " › " + theme.name
            } else {
                result = theme.name
            }
            pathNames[theme.id] = result
            return result
        }
        for theme in themes {
            var visiting: Set<UUID> = []
            _ = pathName(for: theme, visiting: &visiting)
        }

        let roots = (grouped[nil] ?? []).sorted { $0.name < $1.name }
        rootIDs = roots.map(\.id)
        let leftRoots = roots.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }
        let rightRoots = roots.enumerated().compactMap { !$0.offset.isMultiple(of: 2) ? $0.element : nil }

        func maximumDepth(_ node: ThemeNode, depth: Int = 0) -> Int {
            let children = collapsed.contains(node.id) ? [] : (grouped[node.id] ?? [])
            return children.map { maximumDepth($0, depth: depth + 1) }.max() ?? depth
        }
        let leftDepth = leftRoots.map { maximumDepth($0) }.max() ?? 0
        let rightDepth = rightRoots.map { maximumDepth($0) }.max() ?? 0
        let centerX = CGFloat(leftDepth + 1) * 250 + 210
        let rowHeight: CGFloat = 68
        var leftIDs: [UUID] = [], rightIDs: [UUID] = []

        func place(_ node: ThemeNode, depth: Int, direction: CGFloat, row: inout Int, sideIDs: inout [UUID]) -> CGFloat {
            sideIDs.append(node.id)
            let children = collapsed.contains(node.id) ? [] : (grouped[node.id] ?? []).sorted { $0.name < $1.name }
            let centerRow: CGFloat
            if children.isEmpty {
                centerRow = CGFloat(row)
                row += 1
            } else {
                var childRows: [CGFloat] = []
                for child in children {
                    edges.append(Edge(parent: node.id, child: child.id))
                    childRows.append(place(child, depth: depth + 1, direction: direction, row: &row, sideIDs: &sideIDs))
                }
                centerRow = ((childRows.first ?? 0) + (childRows.last ?? 0)) / 2
            }
            let x = direction < 0
                ? centerX - 240 - 190 - CGFloat(depth) * 250
                : centerX + 240 + CGFloat(depth) * 250
            positions[node.id] = CGPoint(x: x, y: centerRow * rowHeight)
            return centerRow
        }

        var leftRows = 0, rightRows = 0
        for root in leftRoots { _ = place(root, depth: 0, direction: -1, row: &leftRows, sideIDs: &leftIDs) }
        for root in rightRoots { _ = place(root, depth: 0, direction: 1, row: &rightRows, sideIDs: &rightIDs) }

        let totalRows = max(leftRows, rightRows, 1)
        let leftShift = CGFloat(totalRows - leftRows) * rowHeight / 2
        let rightShift = CGFloat(totalRows - rightRows) * rowHeight / 2
        for id in leftIDs { positions[id]?.y += leftShift }
        for id in rightIDs { positions[id]?.y += rightShift }

        let rightEdge = centerX + 240 + CGFloat(rightDepth) * 250 + 190
        size = CGSize(width: max(rightEdge + 30, centerX + 240), height: CGFloat(totalRows) * rowHeight + 50)
        centerPosition = CGPoint(x: centerX - 70, y: max(12, (size.height - 48) / 2))
    }
}

enum ThemePalette {
    static func color(_ index: Int) -> Color {
        [.orange, .yellow, .blue, .purple, .mint, .pink][abs(index) % 6]
    }
}
