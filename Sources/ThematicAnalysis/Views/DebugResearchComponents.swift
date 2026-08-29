import SwiftUI

struct DebugSectionTitle: View {
    let title: String
    let subtitle: String
    var symbol: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3).fontWeight(.semibold)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct DebugMetadataPill: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10), in: Capsule())
    }
}

struct DebugExcerptCard: View {
    let excerpt: DebugResearchExcerpt
    let dataset: DebugResearchDataset
    var emphasized = false

    private var participant: DebugResearchParticipant? { dataset.participant(excerpt.participantID) }
    private var participantColor: Color {
        let index = dataset.participants.firstIndex { $0.id == excerpt.participantID } ?? 0
        return ThemePalette.color(index)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(participantColor).frame(width: 8, height: 8)
                Text(participant?.name ?? "Unknown participant").fontWeight(.semibold)
                if let role = participant?.role {
                    Text(role).foregroundStyle(.secondary)
                }
                Spacer()
                Text(excerpt.time).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption)

            Text(excerpt.text)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 6) {
                ForEach(excerpt.codeIDs.sorted(), id: \.self) { codeID in
                    if let code = dataset.code(codeID) {
                        Text(code.name)
                            .font(.caption2)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(ThemePalette.color(code.colorIndex).opacity(0.12), in: Capsule())
                    }
                }
            }

            if !excerpt.analyticMemo.isEmpty {
                Label(excerpt.analyticMemo, systemImage: "text.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(emphasized ? participantColor.opacity(0.10) : Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(participantColor).frame(width: 3).padding(.vertical, 8)
        }
    }
}

struct DebugEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "magnifyingglass", description: Text(message))
            .frame(maxWidth: .infinity, minHeight: 220)
    }
}
