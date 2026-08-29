import Foundation

enum ProjectResearchDatasetBuilder {
    static func build(_ project: AnalysisProject) -> DebugResearchDataset {
        let themesByID = Dictionary(uniqueKeysWithValues: project.themes.map { ($0.id, $0) })

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

        let participants = project.interviews.map { interview in
            DebugResearchParticipant(
                id: interview.id.uuidString,
                name: interview.participant,
                role: interview.participantDetails?.occupation ?? "",
                usageGroup: interview.participantDetails?.gender.nilIfBlank ?? "All participants"
            )
        }

        let codebook = project.themes.map { theme in
            DebugCodebookEntry(
                id: theme.id.uuidString,
                name: theme.name,
                parentID: theme.parentID?.uuidString,
                status: .active,
                definition: theme.note ?? "",
                includeWhen: "",
                excludeWhen: "",
                example: "",
                revision: 1,
                colorIndex: theme.colorIndex
            )
        }

        var excerpts: [DebugResearchExcerpt] = []
        for interview in project.interviews {
            let segmentsByID = Dictionary(uniqueKeysWithValues: interview.segments.map { ($0.id, $0) })
            for unit in interview.codingUnits {
                let segments = unit.segmentIDs.compactMap { segmentsByID[$0] }.sorted { $0.order < $1.order }
                let start = segments.first?.start ?? ""
                let end = segments.last?.end ?? ""
                excerpts.append(
                    DebugResearchExcerpt(
                        id: unit.id.uuidString,
                        participantID: interview.id.uuidString,
                        time: [start, end].filter { !$0.isEmpty }.joined(separator: "–"),
                        text: segments.map(\.text).joined(separator: " "),
                        codeIDs: Set(unit.themeIDs.map(\.uuidString)),
                        analyticMemo: unit.memo
                    )
                )
            }
        }

        let rootThemes = project.themes
            .filter { $0.parentID == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let candidateThemes = rootThemes.map { theme in
            let evidenceIDs = project.interviews.flatMap { interview in
                interview.codingUnits.compactMap { unit in
                    unit.themeIDs.contains(where: { isDescendant($0, of: theme.id) })
                        ? unit.id.uuidString
                        : nil
                }
            }
            return DebugCandidateTheme(
                id: theme.id.uuidString,
                title: theme.name,
                stage: .final,
                centralConcept: theme.note ?? "",
                scope: "",
                codeIDs: project.themes.filter { isDescendant($0.id, of: theme.id) }.map { $0.id.uuidString },
                evidenceIDs: evidenceIDs,
                contradictoryEvidenceIDs: [],
                analyticNarrative: theme.note ?? "",
                frameworkSummaries: [:],
                colorIndex: theme.colorIndex
            )
        }

        return DebugResearchDataset(
            participants: participants,
            codebook: codebook,
            excerpts: excerpts,
            candidateThemes: candidateThemes,
            journal: []
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
