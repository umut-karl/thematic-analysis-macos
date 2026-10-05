import SwiftUI

struct DebugComparisonQueryView: View {
    let dataset: DebugResearchDataset
    @State private var firstCodeID = "helper"
    @State private var secondCodeID = "partner"
    @State private var queryOperator: DebugQueryOperator = .and
    @State private var usageGroup: String?

    private var selectableCodes: [DebugCodebookEntry] {
        dataset.codebook.filter { $0.parentID == nil }
    }

    private var usageGroups: [String] {
        Array(Set(dataset.participants.map(\.usageGroup))).sorted()
    }

    private var results: [DebugResearchExcerpt] {
        dataset.query(
            firstCodeID: firstCodeID,
            secondCodeID: secondCodeID,
            operator: queryOperator,
            usageGroup: usageGroup
        )
    }

    private var resultParticipantCount: Int { Set(results.map(\.participantID)).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DebugSectionTitle(
                title: "Tema listesi yerine araştırma sorusu sorun",
                subtitle: "Mantıksal operatörleri katılımcı gruplarıyla birleştirerek kodların nerede birlikte ya da ayrı çalıştığını görün.",
                symbol: "line.3.horizontal.decrease.circle"
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("Sorgu oluşturucu").font(.headline)
                HStack(spacing: 10) {
                    Picker("Birinci kod", selection: $firstCodeID) {
                        ForEach(selectableCodes) { Text($0.name).tag($0.id) }
                    }
                    .frame(width: 220)

                    Picker("Operatör", selection: $queryOperator) {
                        ForEach(DebugQueryOperator.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 230)

                    Picker("İkinci kod", selection: $secondCodeID) {
                        ForEach(selectableCodes) { Text($0.name).tag($0.id) }
                    }
                    .frame(width: 220)

                    Divider().frame(height: 24)

                    Picker("Katılımcı grubu", selection: $usageGroup) {
                        Text("Tüm gruplar").tag(Optional<String>.none)
                        ForEach(usageGroups, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    .frame(width: 190)
                    Spacer()
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                DebugQueryMetric(title: "Eşleşen alıntı", value: results.count.formatted(), symbol: "quote.bubble")
                DebugQueryMetric(title: "Erişilen katılımcı", value: "\(resultParticipantCount)/\(dataset.participants.count)", symbol: "person.2")
                DebugQueryMetric(title: "Etkin grup", value: usageGroup ?? "Tüm gruplar", symbol: "person.3.sequence")
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sorgu sonuçları").font(.headline)
                    if results.isEmpty {
                        DebugEmptyState(title: "Eşleşme yok", message: "Kodları, operatörü veya katılımcı grubunu değiştirin.")
                    } else {
                        ForEach(results) { excerpt in
                            DebugExcerptCard(excerpt: excerpt, dataset: dataset)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Gruplara göre karşılaştırma").font(.headline)
                    ForEach(usageGroups, id: \.self) { group in
                        let groupParticipants = dataset.participants.filter { $0.usageGroup == group }
                        let groupResults = dataset.query(
                            firstCodeID: firstCodeID,
                            secondCodeID: secondCodeID,
                            operator: queryOperator,
                            usageGroup: group
                        )
                        let reached = Set(groupResults.map(\.participantID)).count
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(group).font(.callout).fontWeight(.medium)
                                Spacer()
                                Text("\(reached)/\(groupParticipants.count)")
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                            ProgressView(value: Double(reached), total: Double(max(groupParticipants.count, 1)))
                        }
                    }

                    Divider()
                    Text("Kod birlikteliği").font(.headline)
                    CodeCooccurrenceSummary(dataset: dataset, codes: selectableCodes)
                }
                .padding(14)
                .frame(width: 340, alignment: .topLeading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }

            MethodCaution(text: "Birliktelik, iki kodun aynı alıntıya uygulanmasını gösterir; tek başına kavramsal veya nedensel ilişki kanıtlamaz. Sonuçlar mutlaka alıntı bağlamıyla okunmalıdır.")
        }
        .animation(.easeInOut(duration: 0.18), value: results.map(\.id))
    }
}

private struct DebugQueryMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CodeCooccurrenceSummary: View {
    let dataset: DebugResearchDataset
    let codes: [DebugCodebookEntry]

    private var pairs: [(String, String, Int)] {
        var result: [(String, String, Int)] = []
        for firstIndex in codes.indices {
            for secondIndex in codes.indices where secondIndex > firstIndex {
                let first = codes[firstIndex]
                let second = codes[secondIndex]
                let count = dataset.excerpts.filter {
                    $0.codeIDs.contains(first.id) && $0.codeIDs.contains(second.id)
                }.count
                if count > 0 { result.append((first.name, second.name, count)) }
            }
        }
        return result.sorted { $0.2 > $1.2 }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(pairs.prefix(5).enumerated()), id: \.offset) { _, pair in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(pair.0) × \(pair.1)")
                        .font(.caption).lineLimit(2)
                    Spacer()
                    Text(pair.2.formatted()).font(.caption).fontWeight(.bold).monospacedDigit()
                }
                .padding(.vertical, 7)
                Divider()
            }
        }
    }
}

struct DebugReflexiveJournalView: View {
    let dataset: DebugResearchDataset
    @State private var phaseFilter: DebugJournalPhase?
    @State private var selectedEntryID = "j3"

    private var entries: [DebugJournalEntry] {
        dataset.journal
            .filter { phaseFilter == nil || $0.phase == phaseFilter }
            .sorted { $0.date > $1.date }
    }

    private var selectedEntry: DebugJournalEntry? {
        entries.first { $0.id == selectedEntryID } ?? entries.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DebugSectionTitle(
                title: "Yalnız sonucu değil, yorumun nasıl değiştiğini kaydedin",
                subtitle: "Refleksif günlük araştırmacının varsayımlarını, tereddütlerini ve temalara ilişkin kararlarını kanıta bağlar.",
                symbol: "book.closed"
            )

            HStack {
                Picker("Analiz aşaması", selection: $phaseFilter) {
                    Text("Tüm analiz aşamaları").tag(Optional<DebugJournalPhase>.none)
                    ForEach(DebugJournalPhase.allCases) { phase in
                        Text(phase.rawValue).tag(Optional(phase))
                    }
                }
                .frame(width: 250)
                Spacer()
                Text("\(entries.count) günlük kaydı")
                    .font(.callout).foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        Button { selectedEntryID = entry.id } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(spacing: 3) {
                                    Circle().fill(.tint).frame(width: 9, height: 9)
                                    Rectangle().fill(.separator).frame(width: 1, height: 42)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title).fontWeight(.semibold).multilineTextAlignment(.leading)
                                    Text(entry.phase.rawValue).font(.caption).foregroundStyle(.secondary)
                                    Text(entry.date, format: .dateTime.day().month(.abbreviated).year())
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                            }
                            .padding(11)
                            .background(selectedEntry?.id == entry.id ? Color.accentColor.opacity(0.10) : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .frame(width: 330)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))

                if let selectedEntry {
                    ReflexiveJournalDetail(entry: selectedEntry, dataset: dataset)
                } else {
                    DebugEmptyState(title: "Kayıt bulunamadı", message: "Başka bir analiz aşaması seçin.")
                }
            }

            MethodCaution(text: "Refleksif günlük bir denetim formu değildir. Amaç araştırmacı öznelliğini ortadan kaldırmak değil, yorumun nasıl üretildiğini açık ve izlenebilir kılmaktır.")
        }
    }
}

private struct ReflexiveJournalDetail: View {
    let entry: DebugJournalEntry
    let dataset: DebugResearchDataset

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title).font(.title2).fontWeight(.semibold)
                    Text(entry.date, format: .dateTime.day().month(.wide).year())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                DebugMetadataPill(title: entry.phase.rawValue, symbol: "arrow.triangle.branch")
            }

            GroupBox("Refleksiyon") {
                Text(entry.reflection).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
            }

            GroupBox("Alınan karar") {
                Label(entry.decision, systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
            }

            if !entry.linkedThemeIDs.isEmpty {
                Text("Bağlı temalar").font(.headline)
                HStack(spacing: 7) {
                    ForEach(entry.linkedThemeIDs, id: \.self) { id in
                        if let theme = dataset.candidateThemes.first(where: { $0.id == id }) {
                            Text(theme.title).font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(ThemePalette.color(theme.colorIndex).opacity(0.12), in: Capsule())
                        }
                    }
                }
            }

            Text("Karara dayanak olan alıntılar").font(.headline)
            ForEach(entry.linkedExcerptIDs.compactMap(dataset.excerpt)) { excerpt in
                DebugExcerptCard(excerpt: excerpt, dataset: dataset)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
    }
}
