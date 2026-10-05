import SwiftUI

struct DebugEvidenceReportView: View {
    let dataset: DebugResearchDataset
    @State private var selectedThemeID = "trust-opacity"

    private var selectedTheme: DebugCandidateTheme {
        dataset.candidateThemes.first { $0.id == selectedThemeID } ?? dataset.candidateThemes[0]
    }

    private var supportingEvidence: [DebugResearchExcerpt] {
        selectedTheme.evidenceIDs.compactMap(dataset.excerpt)
    }

    private var contradictoryEvidence: [DebugResearchExcerpt] {
        selectedTheme.contradictoryEvidenceIDs.compactMap(dataset.excerpt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DebugSectionTitle(
                title: "Analitik iddiayı kanıt zinciriyle birlikte yazın",
                subtitle: "Rapor taslağı tema anlatısını, kapsamını, temsilî alıntıları ve temayı sınırlandıran kanıtları tek bir yazım yüzeyinde birleştirir.",
                symbol: "doc.text.magnifyingglass"
            )

            HStack {
                Picker("Rapor teması", selection: $selectedThemeID) {
                    ForEach(dataset.candidateThemes) { theme in
                        Text(theme.title).tag(theme.id)
                    }
                }
                .frame(width: 280)
                Spacer()
                DebugMetadataPill(title: "\(supportingEvidence.count) destekleyici alıntı", symbol: "checkmark.quote", tint: .green)
                DebugMetadataPill(title: "\(contradictoryEvidence.count) karşıt alıntı", symbol: "arrow.left.arrow.right", tint: .orange)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    ReportOutlineRow(number: "1", title: "Tema adı ve merkezi kavram", isComplete: true)
                    ReportOutlineRow(number: "2", title: "Analitik anlatı", isComplete: true)
                    ReportOutlineRow(number: "3", title: "Destekleyici kanıtlar", isComplete: !supportingEvidence.isEmpty)
                    ReportOutlineRow(number: "4", title: "Karşıt / sınırlandıran kanıt", isComplete: !contradictoryEvidence.isEmpty)
                    ReportOutlineRow(number: "5", title: "Yöntemsel iz", isComplete: true)
                }
                .padding(14)
                .frame(width: 270, alignment: .topLeading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("BULGULAR · TEMA ÖNİZLEMESİ")
                            .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                        Text(selectedTheme.title).font(.largeTitle).fontWeight(.bold)
                        Text(selectedTheme.centralConcept)
                            .font(.title3).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    Text(selectedTheme.analyticNarrative)
                        .font(.body).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    if let first = supportingEvidence.first {
                        reportQuote(first, label: "Temsilî kanıt", tint: ThemePalette.color(selectedTheme.colorIndex))
                    }

                    if supportingEvidence.count > 1 {
                        Text("Kanıt çeşitliliği").font(.headline)
                        ForEach(supportingEvidence.dropFirst().prefix(2)) { excerpt in
                            DebugExcerptCard(excerpt: excerpt, dataset: dataset)
                        }
                    }

                    if let contradiction = contradictoryEvidence.first {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("Temayı sınırlandıran kanıt", systemImage: "arrow.left.arrow.right")
                                .font(.headline).foregroundStyle(.orange)
                            DebugExcerptCard(excerpt: contradiction, dataset: dataset)
                            Text("Bu alıntı temayı geçersiz kılmaz; insan denetiminin her durumda korunmadığını ve temanın bir ideal ile pratik arasındaki gerilimi de içermesi gerektiğini gösterir.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(13)
                        .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }

                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Yöntemsel iz").font(.headline)
                        Label("\(selectedTheme.codeIDs.count) koddan geliştirildi", systemImage: "tag")
                        Label("\(Set(supportingEvidence.map(\.participantID)).count) farklı katılımcıya dayanıyor", systemImage: "person.2")
                        Label("Tema sınırı ve karşıt kanıt açıklandı", systemImage: "checkmark.seal")
                    }
                    .font(.callout)
                }
                .padding(28)
                .frame(maxWidth: 780, alignment: .topLeading)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 3)
            }

            MethodCaution(text: "Rapor oluşturucu alıntıları otomatik olarak ‘kanıt’ ilan etmemeli. Araştırmacı, alıntının bağlamını ve temayla kurduğu analitik ilişkiyi açıklamaya devam etmelidir.")
        }
        .animation(.easeInOut(duration: 0.18), value: selectedThemeID)
    }

    private func reportQuote(_ excerpt: DebugResearchExcerpt, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            Text("“\(excerpt.text)”")
                .font(.title3).italic()
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack {
                Text(dataset.participant(excerpt.participantID)?.name ?? "Katılımcı").fontWeight(.semibold)
                Text("·")
                Text(excerpt.time).monospacedDigit()
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(15)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 4).padding(.vertical, 8) }
    }
}

private struct ReportOutlineRow: View {
    let number: String
    let title: String
    let isComplete: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(number).font(.caption).fontWeight(.bold)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            Text(title).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? .green : .secondary)
        }
        .padding(.vertical, 4)
    }
}
