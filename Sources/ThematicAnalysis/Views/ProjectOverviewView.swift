import SwiftUI

struct ProjectOverviewView: View {
    @ObservedObject var store: AnalysisStore

    private var totalSegments: Int { store.project.interviews.reduce(0) { $0 + $1.segments.count } }
    private var totalUnits: Int { store.project.interviews.reduce(0) { $0 + $1.codingUnits.count } }
    private var usedThemes: Set<UUID> {
        Set(store.project.interviews.flatMap(\.codingUnits).flatMap(\.themeIDs))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.project.name).font(.largeTitle).fontWeight(.semibold)
                    Text("Cross-case workspace").foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    MetricCard(title: "Interview", value: store.project.interviews.count, symbol: "person.2")
                    MetricCard(title: "Transcript Rows", value: totalSegments, symbol: "text.alignleft")
                    MetricCard(title: "Coding Units", value: totalUnits, symbol: "tag")
                    MetricCard(title: "Themes Used", value: usedThemes.count, symbol: "point.3.connected.trianglepath.dotted")
                }
                GroupBox("Interviews") {
                    VStack(spacing: 0) {
                        ForEach(store.project.interviews) { interview in
                            Button {
                                store.selectedInterviewID = interview.id
                            } label: {
                                HStack {
                                    Image(systemName: "person.crop.rectangle").foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(interview.name).fontWeight(.medium)
                                        Text(interview.participant).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    (Text(interview.segments.count.formatted()) + Text(" row(s)")).foregroundStyle(.secondary)
                                    (Text(interview.codingUnits.count.formatted()) + Text(" coding item(s)")).frame(width: 90, alignment: .trailing)
                                }.contentShape(Rectangle()).padding(.vertical, 9)
                            }.buttonStyle(.plain)
                            if interview.id != store.project.interviews.last?.id { Divider() }
                        }
                    }.padding(.horizontal, 8)
                }
                GroupBox("Most Used Themes") {
                    VStack(spacing: 10) {
                        ForEach(themeUsage.prefix(8), id: \.id) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                ProgressView(value: Double(item.count), total: Double(max(themeUsage.first?.count ?? 1, 1)))
                                    .frame(width: 180)
                                Text(item.count.formatted()).monospacedDigit().frame(width: 32, alignment: .trailing)
                            }
                        }
                        if themeUsage.isEmpty { Text("No theme usage yet.").foregroundStyle(.secondary) }
                    }.padding(8)
                }
                Text("Counts show the distribution of coding records, not the importance of themes.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(22).frame(maxWidth: 1000, alignment: .leading)
        }
    }

    private var themeUsage: [(id: UUID, name: String, count: Int)] {
        let all = store.project.interviews.flatMap(\.codingUnits).flatMap(\.themeIDs)
        return Dictionary(grouping: all, by: { $0 }).compactMap { id, values in
            guard let theme = store.project.themes.first(where: { $0.id == id }) else { return nil }
            return (id, theme.name, values.count)
        }.sorted { $0.count > $1.count }
    }
}

private struct MetricCard: View {
    let title: String
    let value: Int
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text(value.formatted()).font(.title).fontWeight(.semibold).monospacedDigit()
            Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
