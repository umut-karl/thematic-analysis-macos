import SwiftUI

struct DebugLabOverviewView: View {
    let research: DebugResearchDataset

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DebugSectionTitle(
                title: "Deneysel araştırma çalışma alanı",
                subtitle: "Sol menüdeki her araç aynı örnek görüşme setini kullanır. Böylece kod kitabından rapora kadar olan zinciri gerçek proje verisine dokunmadan değerlendirebilirsiniz.",
                symbol: "testtube.2"
            )

            HStack(spacing: 10) {
                DebugMetadataPill(title: "\(research.participants.count) katılımcı", symbol: "person.2")
                DebugMetadataPill(title: "\(research.excerpts.count) alıntı", symbol: "quote.bubble")
                DebugMetadataPill(title: "\(research.codebook.count) kod", symbol: "tag")
                DebugMetadataPill(title: "\(research.candidateThemes.count) tema taslağı", symbol: "rectangle.3.group")
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                overviewCard("Kod Kitabı", "Kodların tanımı, sınırı, örneği ve sürüm durumunu birlikte gösterir.", "books.vertical")
                overviewCard("Tema Geliştirme Masası", "Kodları aday, gözden geçirilen ve nihai temalar içinde düzenler.", "rectangle.3.group")
                overviewCard("Karşılaştırma ve Sorgu", "AND, OR ve NOT sorgularını katılımcı gruplarıyla birleştirir.", "line.3.horizontal.decrease.circle")
                overviewCard("Refleksif Günlük", "Analitik kararları ve araştırmacının yorum değişimini zaman çizgisinde tutar.", "book.closed")
                overviewCard("Kanıta Bağlı Rapor", "Tema anlatısını destekleyici ve karşıt alıntılarla birlikte önizler.", "doc.text.magnifyingglass")
                overviewCard("Framework Matrix", "Katılımcı × tema hücrelerinde kısa analitik özet ve kanıt sunar.", "tablecells")
            }

            MethodCaution(text: "Bu ekranlardaki bütün içerik örnek veridir. Hiçbir düzenleme, filtre veya seçim mevcut proje verisine kaydedilmez.")
        }
    }

    private func overviewCard(_ title: String, _ description: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).fontWeight(.semibold)
                Text(description).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
    }
}

struct DebugCodebookView: View {
    let dataset: DebugResearchDataset
    @State private var query = ""
    @State private var statusFilter: DebugCodeStatus?
    @State private var selectedCodeID = "helper"

    private var filteredCodes: [DebugCodebookEntry] {
        dataset.codebook.filter { code in
            let matchesStatus = statusFilter == nil || code.status == statusFilter
            let searchable = [code.name, code.definition, code.includeWhen, code.excludeWhen].joined(separator: " ")
            let matchesQuery = query.isEmpty || searchable.localizedCaseInsensitiveContains(query)
            return matchesStatus && matchesQuery
        }
    }

    private var selectedCode: DebugCodebookEntry? {
        dataset.code(selectedCodeID) ?? filteredCodes.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DebugSectionTitle(
                title: "Kod sistemini yalnız adlardan ibaret bırakmayın",
                subtitle: "Bu prototip bir kodun ne zaman kullanılacağını, ne zaman kullanılmayacağını ve hangi sürümde olduğunu görünür kılar.",
                symbol: "books.vertical"
            )

            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Kod adı, tanım veya ölçüt ara", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 9)
                .frame(maxWidth: 460, minHeight: 32)
                .background(.background, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator))

                Picker("Durum", selection: $statusFilter) {
                    Text("Tüm durumlar").tag(Optional<DebugCodeStatus>.none)
                    ForEach(DebugCodeStatus.allCases) { status in
                        Text(status.rawValue).tag(Optional(status))
                    }
                }
                .frame(width: 180)
                Spacer()
                Text("\(filteredCodes.count) / \(dataset.codebook.count) kod")
                    .font(.callout).foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    ForEach(filteredCodes) { code in
                        Button { selectedCodeID = code.id } label: {
                            HStack(spacing: 9) {
                                Circle().fill(ThemePalette.color(code.colorIndex)).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(code.name).fontWeight(code.parentID == nil ? .semibold : .regular)
                                    Text(code.parentID == nil ? "Ana kod" : "Alt kod")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(.leading, code.parentID == nil ? 0 : 15)
                                Spacer()
                                CodeStatusBadge(status: code.status)
                            }
                            .padding(.horizontal, 11).padding(.vertical, 9)
                            .background(selectedCode?.id == code.id ? ThemePalette.color(code.colorIndex).opacity(0.12) : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .frame(width: 340)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))

                if let selectedCode {
                    CodebookDetailCard(code: selectedCode, dataset: dataset)
                } else {
                    DebugEmptyState(title: "Kod bulunamadı", message: "Arama veya durum filtresini değiştirin.")
                }
            }

            MethodCaution(text: "Kod tanımı analiz sırasında değişebilir. Sürüm numarası ve karar günlüğü, kodlamanın hangi ölçütle yapıldığını geriye dönük olarak açıklayabilmek içindir.")
        }
    }
}

private struct CodeStatusBadge: View {
    let status: DebugCodeStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .draft: .secondary
        case .active: .green
        case .review: .orange
        case .retired: .red
        }
    }
}

private struct CodebookDetailCard: View {
    let code: DebugCodebookEntry
    let dataset: DebugResearchDataset

    private var examples: [DebugResearchExcerpt] {
        dataset.excerpts.filter { $0.codeIDs.contains(code.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(code.name).font(.title2).fontWeight(.semibold)
                    if let parentID = code.parentID, let parent = dataset.code(parentID) {
                        Text("\(parent.name) › \(code.name)").foregroundStyle(.secondary)
                    } else {
                        Text("Ana kod").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                CodeStatusBadge(status: code.status)
                DebugMetadataPill(title: "Sürüm \(code.revision)", symbol: "clock.arrow.circlepath")
            }

            detailSection("Tanım", code.definition, "text.alignleft")
            HStack(alignment: .top, spacing: 12) {
                detailSection("Dahil et", code.includeWhen, "checkmark.circle")
                detailSection("Dışarıda bırak", code.excludeWhen, "xmark.circle")
            }
            detailSection("Kod kitabı örneği", "“\(code.example)”", "quote.opening")

            Divider()
            Text("Bağlı örnek alıntılar · \(examples.count)")
                .font(.headline)
            ForEach(examples.prefix(2)) { excerpt in
                DebugExcerptCard(excerpt: excerpt, dataset: dataset)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
    }

    private func detailSection(_ title: String, _ text: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DebugThemeWorkbenchView: View {
    let dataset: DebugResearchDataset
    @State private var selectedThemeID = "controlled-partnership"

    private var selectedTheme: DebugCandidateTheme? {
        dataset.candidateThemes.first { $0.id == selectedThemeID } ?? dataset.candidateThemes.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DebugSectionTitle(
                title: "Kodlardan temaya geçişi görünür bir süreç yapın",
                subtitle: "Kartlar yalnız başlık değil; merkezi kavram, kapsam, bağlı kodlar ve karşıt kanıt taşıyan analitik nesnelerdir.",
                symbol: "rectangle.3.group"
            )

            HStack(alignment: .top, spacing: 12) {
                ForEach(DebugThemeStage.allCases) { stage in
                    ThemeStageColumn(
                        stage: stage,
                        themes: dataset.candidateThemes.filter { $0.stage == stage },
                        selectedThemeID: $selectedThemeID,
                        dataset: dataset
                    )
                }
            }

            if let selectedTheme {
                ThemeDevelopmentDetail(theme: selectedTheme, dataset: dataset)
            }
        }
    }
}

private struct ThemeStageColumn: View {
    let stage: DebugThemeStage
    let themes: [DebugCandidateTheme]
    @Binding var selectedThemeID: String
    let dataset: DebugResearchDataset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(stage.rawValue).fontWeight(.semibold)
                Spacer()
                Text(themes.count.formatted()).font(.caption).foregroundStyle(.secondary)
            }

            ForEach(themes) { theme in
                Button { selectedThemeID = theme.id } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            Circle().fill(ThemePalette.color(theme.colorIndex)).frame(width: 8, height: 8)
                            Text(theme.title).fontWeight(.semibold).multilineTextAlignment(.leading)
                        }
                        Text(theme.centralConcept).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(4).multilineTextAlignment(.leading)
                        HStack {
                            Label("\(theme.codeIDs.count) kod", systemImage: "tag")
                            Label("\(theme.evidenceIDs.count) kanıt", systemImage: "quote.bubble")
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(selectedThemeID == theme.id ? ThemePalette.color(theme.colorIndex).opacity(0.14) : Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(selectedThemeID == theme.id ? ThemePalette.color(theme.colorIndex) : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }

            if themes.isEmpty {
                Text("Bu aşamada tema yok")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct ThemeDevelopmentDetail: View {
    let theme: DebugCandidateTheme
    let dataset: DebugResearchDataset

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(theme.title).font(.title2).fontWeight(.semibold)
                    Text(theme.stage.rawValue).foregroundStyle(.secondary)
                }
                Spacer()
                DebugMetadataPill(title: "\(theme.evidenceIDs.count) destekleyici", symbol: "checkmark.quote", tint: .green)
                DebugMetadataPill(title: "\(theme.contradictoryEvidenceIDs.count) karşıt", symbol: "arrow.left.arrow.right", tint: .orange)
            }

            GroupBox("Merkezi düzenleyici kavram") {
                Text(theme.centralConcept).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            }
            GroupBox("Kapsam ve sınırlar") {
                Text(theme.scope).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Bağlı kodlar").font(.headline)
                HStack(spacing: 7) {
                    ForEach(theme.codeIDs, id: \.self) { codeID in
                        if let code = dataset.code(codeID) {
                            Text(code.name).font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(ThemePalette.color(code.colorIndex).opacity(0.12), in: Capsule())
                        }
                    }
                }
            }

            Text("Analitik anlatı").font(.headline)
            Text(theme.analyticNarrative).fixedSize(horizontal: false, vertical: true)

            if let evidence = theme.evidenceIDs.first.flatMap(dataset.excerpt) {
                Text("Temsilî kanıt").font(.headline)
                DebugExcerptCard(excerpt: evidence, dataset: dataset, emphasized: true)
            }
            if let contradiction = theme.contradictoryEvidenceIDs.first.flatMap(dataset.excerpt) {
                Text("Temayı sınırlandıran kanıt").font(.headline)
                DebugExcerptCard(excerpt: contradiction, dataset: dataset)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.separator))
    }
}
