import Foundation

struct DebugAnalysisDataset {
    struct Theme: Identifiable, Hashable {
        let id: String
        let name: String
        let path: String
        let colorIndex: Int
    }

    struct Participant: Identifiable, Hashable {
        let id: String
        let name: String
    }

    struct Metric: Identifiable {
        let theme: Theme
        let occurrenceCount: Int
        let participantCount: Int
        let participantTotal: Int
        let occurrenceTotal: Int

        var id: String { theme.id }
        var prevalence: Double {
            guard participantTotal > 0 else { return 0 }
            return Double(participantCount) / Double(participantTotal)
        }
        var occurrenceShare: Double {
            guard occurrenceTotal > 0 else { return 0 }
            return Double(occurrenceCount) / Double(occurrenceTotal)
        }
    }

    let participants: [Participant]
    let themes: [Theme]
    let counts: [String: [String: Int]]

    var totalOccurrences: Int {
        participants.reduce(0) { total, participant in
            total + themes.reduce(0) { $0 + count(participantID: participant.id, themeID: $1.id) }
        }
    }

    var metrics: [Metric] {
        let occurrenceTotal = totalOccurrences
        return themes.map { theme in
            let values = participants.map { count(participantID: $0.id, themeID: theme.id) }
            return Metric(
                theme: theme,
                occurrenceCount: values.reduce(0, +),
                participantCount: values.filter { $0 > 0 }.count,
                participantTotal: participants.count,
                occurrenceTotal: occurrenceTotal
            )
        }
    }

    func count(participantID: String, themeID: String) -> Int {
        counts[participantID]?[themeID] ?? 0
    }

    func matrixScore(participantID: String, themeID: String, strongThreshold: Int) -> Int {
        let value = count(participantID: participantID, themeID: themeID)
        if value == 0 { return 0 }
        return value >= strongThreshold ? 2 : 1
    }
}

enum DebugAnalyticsEngine {
    static func project(_ project: AnalysisProject, focusThemeID: UUID?, themeLimit: Int) -> DebugAnalysisDataset {
        let themesByID = Dictionary(uniqueKeysWithValues: project.themes.map { ($0.id, $0) })
        let children = Dictionary(grouping: project.themes, by: \.parentID)
        var candidates: [ThemeNode]
        if let focusThemeID {
            candidates = children[focusThemeID] ?? []
            if candidates.isEmpty, let focus = themesByID[focusThemeID] { candidates = [focus] }
        } else {
            candidates = children[nil] ?? []
        }

        func isDescendant(_ candidateID: UUID, of ancestorID: UUID) -> Bool {
            var current = themesByID[candidateID]
            var visited: Set<UUID> = []
            while let node = current, !visited.contains(node.id) {
                if node.id == ancestorID { return true }
                visited.insert(node.id)
                current = node.parentID.flatMap { themesByID[$0] }
            }
            return false
        }

        func pathName(_ id: UUID) -> String {
            var names: [String] = []
            var current = themesByID[id]
            var visited: Set<UUID> = []
            while let node = current, !visited.contains(node.id) {
                names.append(node.name)
                visited.insert(node.id)
                current = node.parentID.flatMap { themesByID[$0] }
            }
            return names.reversed().joined(separator: " › ")
        }

        var rawCounts: [String: [String: Int]] = [:]
        for interview in project.interviews {
            let participantID = interview.id.uuidString
            for theme in candidates {
                let count = interview.codingUnits.reduce(0) { partial, unit in
                    partial + (unit.themeIDs.contains(where: { isDescendant($0, of: theme.id) }) ? 1 : 0)
                }
                rawCounts[participantID, default: [:]][theme.id.uuidString] = count
            }
        }

        candidates.sort { left, right in
            let leftTotal = project.interviews.reduce(0) { $0 + (rawCounts[$1.id.uuidString]?[left.id.uuidString] ?? 0) }
            let rightTotal = project.interviews.reduce(0) { $0 + (rawCounts[$1.id.uuidString]?[right.id.uuidString] ?? 0) }
            if leftTotal != rightTotal { return leftTotal > rightTotal }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
        candidates = Array(candidates.prefix(max(themeLimit, 1)))

        return DebugAnalysisDataset(
            participants: project.interviews.map { .init(id: $0.id.uuidString, name: $0.participant) },
            themes: candidates.map {
                .init(id: $0.id.uuidString, name: $0.name, path: pathName($0.id), colorIndex: $0.colorIndex)
            },
            counts: rawCounts
        )
    }

}
