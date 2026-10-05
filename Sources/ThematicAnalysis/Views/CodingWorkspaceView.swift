import SwiftUI

struct CodingWorkspaceView: View {
    @ObservedObject var store: AnalysisStore
    @State private var memo = ""
    @State private var themePath: [UUID] = []

    var body: some View {
        HSplitView {
            TranscriptTableView(store: store, codingMode: true)
                .frame(minWidth: 480, idealWidth: 760)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Kodlama Alanı").font(.headline)
                    if store.selectedSegmentIDs.isEmpty {
                        ContentUnavailableView(
                            "Önce satır seçin",
                            systemImage: "cursorarrow.click.2",
                            description: Text("Aynı konuşmanın art arda gelen satırlarını birlikte seçerek tek bir kodlama birimi oluşturabilirsiniz.")
                        )
                    } else {
                        GroupBox("Seçilen ifade") {
                            Text(store.selectedText).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                                .lineLimit(2...8)
                        }
                        ThemePickerView(
                            store: store,
                            selectedThemeIDs: $store.selectedThemeIDs,
                            path: $themePath,
                            removeAssigned: store.removeThemeFromCurrentSelection
                        )
                        HStack {
                            Button("Temayı Kaydet ve Devam Et") {
                                guard let active = themePath.last else { return }
                                _ = store.saveCodingSelection(themeIDs: [active], memo: memo, keepSelection: true)
                                themePath.removeAll()
                            }
                            .disabled(themePath.isEmpty)
                            .help("Bu temayı hemen kaydet ve aynı ifadeye başka bir tema seç")
                            Spacer()
                            Text("Seçili ifade açık kalır.").font(.caption).foregroundStyle(.secondary)
                        }
                        TextField("Analitik not (isteğe bağlı)", text: $memo, axis: .vertical)
                            .lineLimit(2...5).textFieldStyle(.roundedBorder)
                        Button("Kaydet ve Kodlamayı Bitir") {
                            var ids = store.selectedThemeIDs
                            if let active = themePath.last { ids.insert(active) }
                            _ = store.saveCodingSelection(themeIDs: ids, memo: memo, keepSelection: false)
                            memo = ""; themePath.removeAll()
                        }
                        .keyboardShortcut(.return, modifiers: [.command])
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .disabled(themePath.isEmpty && store.selectedThemeIDs.isEmpty)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }.frame(minWidth: 390, idealWidth: 560)
        }
        .onAppear { store.selectedThemeIDs = store.themeIDsForCurrentSelection() }
        .onChange(of: store.selectedSegmentIDs) {
            store.selectedThemeIDs = store.themeIDsForCurrentSelection()
            themePath.removeAll()
        }
    }
}

private struct ThemePickerView: View {
    @ObservedObject var store: AnalysisStore
    @Binding var selectedThemeIDs: Set<UUID>
    @Binding var path: [UUID]
    let removeAssigned: (UUID) -> Void
    @State private var newName = ""
    @State private var themeQuery = ""

    private var currentParent: UUID? { path.last }

    var body: some View {
        GroupBox("Tema yolu seç") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ThemeHierarchyPickerButton(
                        store: store,
                        title: path.last.map(store.themeName) ?? AppLocalization.string("Hiyerarşiden Tema Seç…"),
                        choose: chooseTheme
                    )
                    if !path.isEmpty {
                        Button { path.removeAll() } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.plain).help("Tema seçimini temizle")
                    }
                }

                TextField("Tema adında veya yolunda ara", text: $themeQuery)
                    .textFieldStyle(.roundedBorder)
                if !themeQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(searchResults) { theme in
                            Button { chooseTheme(theme.id); themeQuery = "" } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(theme.name).font(.callout).fontWeight(.medium).lineLimit(nil)
                                    Text(store.themePathName(for: theme.id)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(8).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                }

                if !path.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Seçilen yol").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                        ForEach(Array(path.enumerated()), id: \.offset) { level, id in
                            if let theme = store.project.themes.first(where: { $0.id == id }) {
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(ThemePalette.color(theme.colorIndex)).frame(width: 7, height: 7).padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 1) {
                                        if level == 0 {
                                            Text("Ana tema").font(.caption2).foregroundStyle(.tertiary)
                                        } else {
                                            (Text(level.formatted()) + Text(". alt düzey"))
                                                .font(.caption2).foregroundStyle(.tertiary)
                                        }
                                        Text(theme.name).font(.callout).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    .padding(10).background(.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                }

                HStack {
                    TextField(
                        AppLocalization.string(currentParent == nil ? "Yeni ana tema" : "Bu düzeye yeni alt tema"),
                        text: $newName
                    )
                    Button {
                        if let id = store.addTheme(name: newName, parentID: currentParent) {
                            path.append(id); newName = ""
                        }
                    } label: { Image(systemName: "plus") }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !selectedThemeIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bu ifadeye atanmış temalar").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                        ForEach(selectedThemeIDs.sorted(by: { store.themePathName(for: $0) < store.themePathName(for: $1) }), id: \.self) { id in
                            let color = store.project.themes.first(where: { $0.id == id }).map { ThemePalette.color($0.colorIndex) } ?? .accentColor
                            HStack(alignment: .top, spacing: 8) {
                                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
                                Text(store.themePathName(for: id))
                                    .font(.caption).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button { removeAssigned(id) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Tema atamasını kaldır")
                            }
                            .padding(8).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
            }.padding(.top, 4)
        }
    }

    private var searchResults: [ThemeNode] {
        let query = themeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return store.project.themes.filter {
            $0.name.localizedCaseInsensitiveContains(query) || store.themePathName(for: $0.id).localizedCaseInsensitiveContains(query)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseTheme(_ id: UUID) {
        path = store.themePath(for: id).map(\.id)
    }
}
