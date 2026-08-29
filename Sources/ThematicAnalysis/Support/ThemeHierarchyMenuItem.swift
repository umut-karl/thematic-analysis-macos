import SwiftUI

struct ThemeHierarchyMenuItem: View {
    let node: ThemeNode
    @ObservedObject var store: AnalysisStore
    let choose: (UUID) -> Void

    var body: some View {
        let children = store.children(of: node.id)
        if children.isEmpty {
            Button(node.name) { choose(node.id) }
        } else {
            Menu(node.name) {
                Button("Choose this theme") { choose(node.id) }
                Divider()
                ForEach(children) { child in
                    ThemeHierarchyMenuItem(node: child, store: store, choose: choose)
                }
            }
        }
    }
}

struct ThemeHierarchyPickerButton: View {
    @ObservedObject var store: AnalysisStore
    let title: String
    var prominent = true
    let choose: (UUID) -> Void
    @State private var isPresented = false

    var body: some View {
        Group {
            if prominent {
                pickerButton.buttonStyle(.borderedProminent)
            } else {
                pickerButton.buttonStyle(.bordered)
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ThemeHierarchyBrowser(store: store) { id in
                choose(id)
                isPresented = false
            }
            .frame(minWidth: 440, idealWidth: 500, minHeight: 520, idealHeight: 620)
        }
        .accessibilityHint("Opens the full theme hierarchy")
    }

    private var pickerButton: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label(title, systemImage: "list.bullet.indent")
                .lineLimit(1)
        }
    }
}

private struct ThemeHierarchyBrowser: View {
    @ObservedObject var store: AnalysisStore
    let choose: (UUID) -> Void
    @State private var query = ""
    @State private var expandedThemeIDs: Set<UUID> = []

    private var branchIDs: Set<UUID> {
        Set(store.project.themes.compactMap { theme in
            store.children(of: theme.id).isEmpty ? nil : theme.id
        })
    }

    private var searchResults: [ThemeNode] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        return store.project.themes.filter {
            $0.name.localizedCaseInsensitiveContains(clean)
                || store.themePathName(for: $0.id).localizedCaseInsensitiveContains(clean)
        }
        .sorted { store.themePathName(for: $0.id).localizedCaseInsensitiveCompare(store.themePathName(for: $1.id)) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose Theme").font(.headline)
                    Text(store.project.themes.count.formatted()) + Text(" themes · full hierarchy")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Expand All") { withAnimation(.easeInOut(duration: 0.2)) { expandedThemeIDs = branchIDs } }
                    .disabled(expandedThemeIDs == branchIDs)
                Button("Collapse") { withAnimation(.easeInOut(duration: 0.2)) { expandedThemeIDs.removeAll() } }
                    .disabled(expandedThemeIDs.isEmpty)
            }
            .padding(14)

            TextField("Search theme name or path", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 14).padding(.bottom, 10)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ForEach(store.children(of: nil)) { root in
                            ThemeHierarchyBrowserRow(
                                node: root,
                                depth: 0,
                                store: store,
                                expandedThemeIDs: $expandedThemeIDs,
                                choose: choose
                            )
                        }
                    } else if searchResults.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .frame(maxWidth: .infinity).padding(.top, 50)
                    } else {
                        ForEach(searchResults) { theme in
                            Button { choose(theme.id) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(theme.name).fontWeight(.medium)
                                    Text(store.themePathName(for: theme.id))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(8)
            }
        }
        .onAppear { expandedThemeIDs.removeAll() }
    }
}

private struct ThemeHierarchyBrowserRow: View {
    let node: ThemeNode
    let depth: Int
    @ObservedObject var store: AnalysisStore
    @Binding var expandedThemeIDs: Set<UUID>
    let choose: (UUID) -> Void

    private var children: [ThemeNode] { store.children(of: node.id) }
    private var isExpanded: Bool { expandedThemeIDs.contains(node.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if children.isEmpty {
                    Color.clear.frame(width: 22, height: 22)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if isExpanded { expandedThemeIDs.remove(node.id) }
                            else { expandedThemeIDs.insert(node.id) }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption).fontWeight(.semibold)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLocalization.string(isExpanded ? "Collapse subthemes" : "Expand subthemes"))
                }

                Button { choose(node.id) } label: {
                    HStack(spacing: 7) {
                        Circle().fill(ThemePalette.color(node.colorIndex)).frame(width: 7, height: 7)
                        Text(node.name)
                            .font(depth == 0 ? .callout.weight(.semibold) : .callout)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        if !children.isEmpty {
                            Text("\(children.count)").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, CGFloat(depth) * 15)
            .padding(.horizontal, 5).padding(.vertical, 3)

            if isExpanded {
                ForEach(children) { child in
                    ThemeHierarchyBrowserRow(
                        node: child,
                        depth: depth + 1,
                        store: store,
                        expandedThemeIDs: $expandedThemeIDs,
                        choose: choose
                    )
                }
                .transition(.opacity)
            }
        }
    }
}
