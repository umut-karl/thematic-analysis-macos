import SwiftUI

struct SavedAnalysisMemosView: View {
    @StateObject private var memoStore: SavedAnalysisMemoStore
    @State private var query = ""

    init(storageRoot: URL) {
        _memoStore = StateObject(wrappedValue: SavedAnalysisMemoStore(storageRoot: storageRoot))
    }

    private var filteredMemos: [SavedAnalysisMemo] {
        guard !query.isEmpty else { return memoStore.memos }
        return memoStore.memos.filter { memo in
            [memo.title, memo.modelID, memo.methodTitle, memo.promptVersion]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        HSplitView {
            memoList
                .frame(minWidth: 230, idealWidth: 280, maxWidth: 380)
            memoDetail
                .frame(minWidth: 520)
        }
        .onAppear { memoStore.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .analysisMemoSaved)) { _ in
            memoStore.reload()
        }
    }

    private var memoList: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kaydedilen Analizler")
                            .font(.title3.weight(.semibold))
                        (Text(memoStore.memos.count.formatted()) + Text(" kayıtlı analiz"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        memoStore.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Kaydedilen analizleri yenile")
                }

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Kaydedilen analizlerde ara", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Aramayı temizle")
                    }
                }
                .padding(.horizontal, 9)
                .frame(minHeight: 30)
                .background(.background, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator))
            }
            .padding(12)
            .background(.bar)

            Divider()

            List(selection: $memoStore.selectedMemoID) {
                ForEach(filteredMemos) { memo in
                    SavedMemoRow(memo: memo)
                        .tag(memo.id)
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if filteredMemos.isEmpty {
                    ContentUnavailableView {
                        Label(
                            query.isEmpty ? "Henüz kaydedilmiş analiz yok" : "Eşleşen analiz yok",
                            systemImage: query.isEmpty ? "tray" : "magnifyingglass"
                        )
                    } description: {
                        Text(
                            query.isEmpty
                                ? "Analiz Asistanı yanıtındaki “Memo olarak kaydet” düğmesini kullanın."
                                : "Arama ifadesini değiştirin veya temizleyin."
                        )
                    }
                }
            }

            if !memoStore.errorMessage.isEmpty {
                Label(memoStore.errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
            }
        }
    }

    @ViewBuilder
    private var memoDetail: some View {
        if let memo = memoStore.selectedMemo {
            SavedMemoDetail(memo: memo)
        } else {
            ContentUnavailableView(
                "Bir analiz seçin",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Kaydedilmiş analiz notunun içeriği burada görüntülenir.")
            )
        }
    }
}

private struct SavedMemoRow: View {
    let memo: SavedAnalysisMemo

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(memo.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Text(memo.createdAt.formatted(
                        Date.FormatStyle(date: .abbreviated, time: .shortened)
                            .locale(AppLocalization.language.locale)
                    ))
                    if !memo.modelID.isEmpty {
                        Text("·")
                        Text(memo.modelID)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SavedMemoDetail: View {
    let memo: SavedAnalysisMemo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Kaydedilmiş analiz", systemImage: "tray.full")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(memo.title)
                        .font(.largeTitle.weight(.semibold))
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        if !memo.modelID.isEmpty {
                            MemoMetadataPill(title: memo.modelID, symbol: "cpu")
                        }
                        if !memo.methodProfileID.isEmpty {
                            MemoMetadataPill(title: memo.methodTitle, symbol: "list.bullet.clipboard")
                        }
                        if !memo.promptVersion.isEmpty {
                            MemoMetadataPill(
                                title: AppLocalization.string("İstem") + " " + memo.promptVersion,
                                symbol: "checkmark.shield"
                            )
                        }
                        MemoMetadataPill(
                            title: memo.createdAt.formatted(
                                Date.FormatStyle(date: .abbreviated, time: .shortened)
                                    .locale(AppLocalization.language.locale)
                            ),
                            symbol: "calendar"
                        )
                    }
                }

                Label {
                    Text("Bu içerik AI destekli bir analiz notudur; araştırmacı değerlendirmesi olmadan nihai bulgu sayılmaz.")
                } icon: {
                    Image(systemName: "person.badge.shield.checkmark")
                        .foregroundStyle(.tint)
                }
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                Divider()

                ForEach(memo.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        if let title = section.title, !title.isEmpty {
                            Text(title)
                                .font(.title3.weight(.semibold))
                        }
                        MemoMarkdownContent(markdown: section.markdown)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct MemoMetadataPill: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
    }
}

private struct MemoMarkdownContent: View {
    let markdown: String

    private var blocks: [String] {
        markdown.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                let lines = block.components(separatedBy: .newlines).filter { !$0.isEmpty }
                if isMarkdownTable(lines) {
                    MemoMarkdownTable(lines: lines)
                } else if !lines.isEmpty && lines.allSatisfy({ $0.hasPrefix("- ") }) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().frame(width: 5, height: 5)
                                Text(markdown: String(line.dropFirst(2)))
                            }
                        }
                    }
                } else {
                    Text(markdown: block)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func isMarkdownTable(_ lines: [String]) -> Bool {
        lines.count >= 2 && lines[0].hasPrefix("|") && lines[1].contains("---")
    }
}

private struct MemoMarkdownTable: View {
    let lines: [String]

    private var rows: [[String]] {
        lines.enumerated().compactMap { index, line in
            guard index != 1 else { return nil }
            let clean = line.trimmingCharacters(in: CharacterSet(charactersIn: "| "))
            return clean.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\|", with: "|") }
        }
    }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(markdown: cell)
                                .font(rowIndex == 0 ? .caption.weight(.semibold) : .callout)
                                .padding(9)
                                .frame(minWidth: 120, maxWidth: 280, alignment: .leading)
                                .background(rowIndex == 0 ? Color.secondary.opacity(0.12) : Color.clear)
                        }
                    }
                    if rowIndex < rows.count - 1 {
                        Divider().gridCellUnsizedAxes(.horizontal)
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private extension Text {
    init(markdown: String) {
        if let attributed = try? AttributedString(markdown: markdown) {
            self.init(attributed)
        } else {
            self.init(verbatim: markdown)
        }
    }
}
