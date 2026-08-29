import Charts
import SwiftUI

struct DebugLabView: View {
    @ObservedObject var store: AnalysisStore
    let module: DebugLabModule
    @State private var strongThreshold = 2
    @State private var frameworkWorkspace: DebugFrameworkMatrixWorkspace

    init(store: AnalysisStore, module: DebugLabModule) {
        self.store = store
        self.module = module
        let research = ProjectResearchDatasetBuilder.build(store.project)
        _frameworkWorkspace = State(initialValue: DebugFrameworkMatrixWorkspace(dataset: research))
    }

    private var research: DebugResearchDataset {
        ProjectResearchDatasetBuilder.build(store.project)
    }

    private var dataset: DebugAnalysisDataset {
        DebugAnalyticsEngine.project(store.project, focusThemeID: nil, themeLimit: 12)
    }

    var body: some View {
        Group {
            if module == .frameworkMatrix {
                DebugFrameworkMatrixView(dataset: research, workspace: frameworkWorkspace)
            } else {
                ScrollView {
                    Group {
                        switch module {
                        case .profile: DominanceProfileView(dataset: dataset, strongThreshold: $strongThreshold)
                        case .frequency: FrequencyDistributionView(dataset: dataset)
                        case .milesMatrix: ConceptualMatrixView(dataset: dataset, strongThreshold: $strongThreshold)
                        case .prevalence: PrevalenceAnalysisView(dataset: dataset)
                        case .frameworkMatrix: EmptyView()
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 1240, alignment: .leading)
                }
            }
        }
    }
}

private struct DominanceProfileView: View {
    let dataset: DebugAnalysisDataset
    @Binding var strongThreshold: Int
    @State private var sort: DominanceSort = .frequency
    @State private var selectedThemeID: String?

    private var metrics: [DebugAnalysisDataset.Metric] { dataset.metrics }
    private var selectedMetric: DebugAnalysisDataset.Metric? {
        metrics.first(where: { $0.id == (selectedThemeID ?? orderedMetrics.first?.id) })
    }
    private var orderedMetrics: [DebugAnalysisDataset.Metric] {
        metrics.sorted { left, right in
            switch sort {
            case .frequency: return left.occurrenceCount == right.occurrenceCount ? left.theme.name < right.theme.name : left.occurrenceCount > right.occurrenceCount
            case .prevalence: return left.prevalence == right.prevalence ? left.occurrenceCount > right.occurrenceCount : left.prevalence > right.prevalence
            case .matrix: return matrixTotal(left) == matrixTotal(right) ? left.occurrenceCount > right.occurrenceCount : matrixTotal(left) > matrixTotal(right)
            }
        }
    }
    private var maximumOccurrence: Int { max(metrics.map(\.occurrenceCount).max() ?? 1, 1) }
    private var maximumMatrixTotal: Int { max(dataset.participants.count * 2, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Spacer()
                Picker("Sort", selection: $sort) {
                    ForEach(DominanceSort.allCases) { item in Text(LocalizedStringKey(item.rawValue)).tag(item) }
                }
                .frame(width: 170)
                Stepper(value: $strongThreshold, in: 2...5) {
                    Text("Strong: ") + Text("\(strongThreshold)+")
                }
                .frame(width: 110)
            }

            HStack(spacing: 10) {
                DominanceSpotlight(
                    title: "Highest Volume",
                    theme: metrics.max(by: { $0.occurrenceCount < $1.occurrenceCount })?.theme.name ?? "—",
                    value: metrics.max(by: { $0.occurrenceCount < $1.occurrenceCount }).map {
                        "\($0.occurrenceCount) occurrences"
                    } ?? "—",
                    symbol: "chart.bar.fill"
                )
                DominanceSpotlight(
                    title: "Broadest Reach",
                    theme: metrics.max(by: { $0.prevalence < $1.prevalence })?.theme.name ?? "—",
                    value: metrics.max(by: { $0.prevalence < $1.prevalence }).map { $0.prevalence.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                    symbol: "person.3.fill"
                )
                DominanceSpotlight(
                    title: "Strongest Matrix",
                    theme: metrics.max(by: { matrixTotal($0) < matrixTotal($1) })?.theme.name ?? "—",
                    value: metrics.max(by: { matrixTotal($0) < matrixTotal($1) }).map { "\(matrixTotal($0))/\(maximumMatrixTotal) points" } ?? "—",
                    symbol: "square.grid.3x3.fill"
                )
            }

            VStack(spacing: 0) {
                ProfileHeaderRow()
                Divider()
                ForEach(orderedMetrics) { metric in
                    Button { selectedThemeID = metric.id } label: {
                        DominanceProfileRow(
                            metric: metric,
                            dataset: dataset,
                            strongThreshold: strongThreshold,
                            maximumOccurrence: maximumOccurrence,
                            isSelected: selectedMetric?.id == metric.id
                        )
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: sort)

            if let selectedMetric {
                HStack(spacing: 18) {
                    Circle().fill(ThemePalette.color(selectedMetric.theme.colorIndex)).frame(width: 9, height: 9)
                    Text(selectedMetric.theme.name).fontWeight(.semibold)
                    Divider().frame(height: 22)
                    Label("\(selectedMetric.occurrenceCount) occurrences", systemImage: "number")
                    Label("\(selectedMetric.participantCount)/\(selectedMetric.participantTotal) participants", systemImage: "person.2")
                    Label("\(matrixTotal(selectedMetric))/\(maximumMatrixTotal) matrix score", systemImage: "square.grid.3x3")
                    Spacer()
                }
                .font(.callout).padding(12)
                .background(ThemePalette.color(selectedMetric.theme.colorIndex).opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    private func matrixTotal(_ metric: DebugAnalysisDataset.Metric) -> Int {
        dataset.participants.reduce(0) {
            $0 + dataset.matrixScore(participantID: $1.id, themeID: metric.theme.id, strongThreshold: strongThreshold)
        }
    }
}

private enum DominanceSort: String, CaseIterable, Identifiable {
    case frequency = "Frequency"
    case prevalence = "Prevalence"
    case matrix = "Matrix Strength"
    var id: String { rawValue }
}

private struct DominanceSpotlight: View {
    let title: String
    let theme: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary)
                Text(theme).fontWeight(.semibold).lineLimit(2)
                Text(value).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ProfileHeaderRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Theme").frame(width: 150, alignment: .leading)
            Text("Frequency · Weight").frame(width: 145, alignment: .leading)
            Text("Prevalence").frame(width: 120, alignment: .leading)
            Text("Participant Matrix · 0–2").frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 9).background(.bar)
    }
}

private struct DominanceProfileRow: View {
    let metric: DebugAnalysisDataset.Metric
    let dataset: DebugAnalysisDataset
    let strongThreshold: Int
    let maximumOccurrence: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(metric.theme.name).lineLimit(2).multilineTextAlignment(.leading)
            }
            .frame(width: 150, alignment: .leading)

            HStack(spacing: 7) {
                ProgressView(value: Double(metric.occurrenceCount), total: Double(maximumOccurrence))
                    .tint(color)
                Text("\(metric.occurrenceCount) · \(metric.occurrenceShare, format: .percent.precision(.fractionLength(0)))")
                    .font(.caption).monospacedDigit().frame(width: 58, alignment: .trailing)
            }
            .frame(width: 145)

            HStack(spacing: 7) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary).frame(height: 2)
                        Capsule().fill(color).frame(width: proxy.size.width * metric.prevalence, height: 2)
                        Circle().fill(color).frame(width: 9, height: 9)
                            .offset(x: max(0, proxy.size.width * metric.prevalence - 4.5))
                    }
                }
                .frame(height: 10)
                Text(metric.prevalence, format: .percent.precision(.fractionLength(0)))
                    .font(.caption).monospacedDigit().frame(width: 34, alignment: .trailing)
            }
            .frame(width: 120)

            HStack(spacing: 4) {
                ForEach(Array(dataset.participants.prefix(10))) { participant in
                    let score = dataset.matrixScore(participantID: participant.id, themeID: metric.theme.id, strongThreshold: strongThreshold)
                    Text(score.formatted())
                        .font(.caption2).fontWeight(score == 2 ? .bold : .regular).monospacedDigit()
                        .frame(width: 18, height: 18)
                        .background(score == 0 ? Color.secondary.opacity(0.07) : color.opacity(score == 1 ? 0.18 : 0.48), in: RoundedRectangle(cornerRadius: 4))
                        .help("\(participant.name): \(score)")
                }
                if dataset.participants.count > 10 {
                    Text("+\(dataset.participants.count - 10)").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(isSelected ? color.opacity(0.10) : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var color: Color { ThemePalette.color(metric.theme.colorIndex) }
}

private struct FrequencyDistributionView: View {
    let dataset: DebugAnalysisDataset
    private var metrics: [DebugAnalysisDataset.Metric] {
        dataset.metrics.sorted { $0.occurrenceCount > $1.occurrenceCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Chart(metrics) { metric in
                BarMark(
                    x: .value("Coding", metric.occurrenceCount),
                    y: .value("Theme", metric.theme.name)
                )
                .foregroundStyle(ThemePalette.color(metric.theme.colorIndex).gradient)
                .annotation(position: .trailing) {
                    Text("\(metric.occurrenceCount) · \(metric.occurrenceShare, format: .percent.precision(.fractionLength(1)))")
                        .font(.caption).monospacedDigit()
                }
            }
            .chartXAxisLabel("Coding occurrences")
            .frame(height: max(250, CGFloat(metrics.count) * 52))

            DebugResultTable(metrics: metrics, mode: .frequency)
        }
    }
}

private struct PrevalenceAnalysisView: View {
    let dataset: DebugAnalysisDataset
    private var metrics: [DebugAnalysisDataset.Metric] {
        dataset.metrics.sorted {
            $0.prevalence == $1.prevalence ? $0.occurrenceCount > $1.occurrenceCount : $0.prevalence > $1.prevalence
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Chart(metrics) { metric in
                BarMark(
                    x: .value("Prevalence", metric.prevalence * 100),
                    y: .value("Theme", metric.theme.name)
                )
                .foregroundStyle(ThemePalette.color(metric.theme.colorIndex).opacity(0.22))
                .clipShape(Capsule())
                PointMark(
                    x: .value("Prevalence", metric.prevalence * 100),
                    y: .value("Theme", metric.theme.name)
                )
                .symbolSize(90)
                .foregroundStyle(ThemePalette.color(metric.theme.colorIndex))
                .annotation(position: .trailing) {
                    Text("%\(metric.prevalence * 100, format: .number.precision(.fractionLength(0))) · \(metric.participantCount)/\(metric.participantTotal)")
                        .font(.caption).monospacedDigit()
                }
            }
            .chartXScale(domain: 0...100)
            .chartXAxisLabel("Participant prevalence (%)")
            .frame(height: max(250, CGFloat(metrics.count) * 52))

            DebugResultTable(metrics: metrics, mode: .prevalence)
        }
    }
}

private struct ConceptualMatrixView: View {
    let dataset: DebugAnalysisDataset
    @Binding var strongThreshold: Int
    private let participantWidth: CGFloat = 150
    private let themeWidth: CGFloat = 142

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer()
                Stepper(value: $strongThreshold, in: 2...5) {
                    Text("Strong threshold: ") + Text("\(strongThreshold)+") + Text(" occurrence(s)")
                }
                .frame(width: 190)
            }

            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Participant").fontWeight(.semibold).frame(width: participantWidth, alignment: .leading)
                        ForEach(dataset.themes) { theme in
                            Text(theme.name).font(.caption).fontWeight(.semibold).lineLimit(3)
                                .frame(width: themeWidth).frame(minHeight: 48)
                        }
                    }
                    .padding(.vertical, 8).background(.bar)

                    ForEach(Array(dataset.participants.enumerated()), id: \.element.id) { index, participant in
                        HStack(spacing: 0) {
                            Text(participant.name).fontWeight(.medium)
                                .frame(width: participantWidth, alignment: .leading)
                            ForEach(dataset.themes) { theme in
                                MatrixCell(
                                    score: dataset.matrixScore(participantID: participant.id, themeID: theme.id, strongThreshold: strongThreshold),
                                    count: dataset.count(participantID: participant.id, themeID: theme.id),
                                    color: ThemePalette.color(theme.colorIndex)
                                )
                                .frame(width: themeWidth, height: 46)
                            }
                        }
                        .background(index.isMultiple(of: 2) ? Color.secondary.opacity(0.035) : .clear)
                        Divider()
                    }

                    HStack(spacing: 0) {
                        Text("Total Score").fontWeight(.semibold).frame(width: participantWidth, alignment: .leading)
                        ForEach(dataset.themes) { theme in
                            let total = dataset.participants.reduce(0) {
                                $0 + dataset.matrixScore(participantID: $1.id, themeID: theme.id, strongThreshold: strongThreshold)
                            }
                            Text(total.formatted()).fontWeight(.bold).monospacedDigit().frame(width: themeWidth)
                        }
                    }
                    .padding(.vertical, 12).background(.quaternary.opacity(0.55))
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
        }
    }
}

private struct MatrixCell: View {
    let score: Int
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(score.formatted()).font(.headline).monospacedDigit()
            Text(LocalizedStringKey(score == 0 ? "None" : score == 1 ? "Secondary" : "Strong"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(score == 0 ? Color.secondary.opacity(0.05) : color.opacity(score == 1 ? 0.16 : 0.42))
        .overlay(Rectangle().stroke(.separator.opacity(0.45)))
        .help("\(count) coding occurrences")
        .accessibilityLabel(
            "\(score == 0 ? "None" : score == 1 ? "Secondary" : "Strong"), \(count) coding occurrences"
        )
    }
}

private enum DebugResultMode { case frequency, prevalence }

private struct DebugResultTable: View {
    let metrics: [DebugAnalysisDataset.Metric]
    let mode: DebugResultMode

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
            GridRow {
                Text("Row"); Text("Theme"); Text("Coding"); Text("Participant"); Text(LocalizedStringKey(mode == .frequency ? "Weight" : "Prevalence"))
            }
            .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            Divider().gridCellColumns(5)
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                GridRow {
                    Text("\(index + 1)").foregroundStyle(.secondary)
                    Text(metric.theme.name).frame(maxWidth: .infinity, alignment: .leading)
                    Text(metric.occurrenceCount.formatted()).monospacedDigit()
                    Text("\(metric.participantCount)/\(metric.participantTotal)").monospacedDigit()
                    Text((mode == .frequency ? metric.occurrenceShare : metric.prevalence), format: .percent.precision(.fractionLength(1))).monospacedDigit()
                }
            }
        }
        .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct MethodCaution: View {
    let text: String
    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.callout).padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }
}
