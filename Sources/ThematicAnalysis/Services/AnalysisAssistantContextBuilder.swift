import Foundation

enum AnalysisAssistantContextBuilder {
    struct Snapshot: Equatable {
        let json: String
        let evidence: [AnalysisEvidenceLocator]

        var evidenceIDs: Set<String> { Set(evidence.map(\.evidenceID)) }
    }

    private struct Context: Encodable {
        let project: String
        let generatedAt: Date
        let analysisBrief: AnalysisBrief
        let analysisScope: ScopeContext
        let participantCount: Int
        let interviewCount: Int
        let transcriptRowCount: Int
        let codingUnitCount: Int
        let themes: [ThemeContext]
        let codedEvidence: [EvidenceContext]

        private enum CodingKeys: String, CodingKey {
            case project
            case generatedAt = "generated_at"
            case analysisBrief = "analysis_brief"
            case analysisScope = "analysis_scope"
            case participantCount = "participant_count"
            case interviewCount = "interview_count"
            case transcriptRowCount = "transcript_row_count"
            case codingUnitCount = "coding_unit_count"
            case themes
            case codedEvidence = "coded_evidence"
        }
    }

    private struct ScopeContext: Encodable {
        let kind: String
        let title: String
        let surroundingRowCount: Int

        private enum CodingKeys: String, CodingKey {
            case kind, title
            case surroundingRowCount = "surrounding_row_count"
        }
    }

    private struct ThemeContext: Encodable {
        let id: UUID
        let name: String
        let path: String
        let parentID: UUID?
        let narrative: String

        private enum CodingKeys: String, CodingKey {
            case id, name, path, narrative
            case parentID = "parent_id"
        }
    }

    private struct EvidenceContext: Encodable {
        struct TranscriptContext: Encodable {
            let order: Int
            let speaker: String
            let start: String
            let end: String
            let text: String
        }

        let evidenceID: String
        let interviewID: UUID
        let codingUnitID: UUID
        let segmentIDs: [UUID]
        let participant: String
        let interview: String
        let themePaths: [String]
        let excerpt: String
        let memo: String
        let precedingContext: [TranscriptContext]
        let followingContext: [TranscriptContext]

        private enum CodingKeys: String, CodingKey {
            case participant, interview, excerpt, memo
            case evidenceID = "evidence_id"
            case interviewID = "interview_id"
            case codingUnitID = "coding_unit_id"
            case segmentIDs = "segment_ids"
            case themePaths = "theme_paths"
            case precedingContext = "preceding_context"
            case followingContext = "following_context"
        }
    }

    static func makeContext(
        from project: AnalysisProject,
        brief: AnalysisBrief = AnalysisBrief(),
        scope: AnalysisAssistantScope = .project
    ) throws -> String {
        try makeSnapshot(from: project, brief: brief, scope: scope).json
    }

    static func makeSnapshot(
        from project: AnalysisProject,
        brief: AnalysisBrief = AnalysisBrief(),
        scope: AnalysisAssistantScope = .project
    ) throws -> Snapshot {
        let themesByID = Dictionary(uniqueKeysWithValues: project.themes.map { ($0.id, $0) })

        func themePath(_ id: UUID) -> String {
            var names: [String] = []
            var current = themesByID[id]
            var visited: Set<UUID> = []
            while let theme = current, visited.insert(theme.id).inserted {
                names.append(theme.name)
                current = theme.parentID.flatMap { themesByID[$0] }
            }
            return names.reversed().joined(separator: " › ")
        }

        let scopedThemeIDs: Set<UUID>? = {
            guard scope.kind == .theme, let rootID = scope.themeID else { return nil }
            var result: Set<UUID> = [rootID]
            var didAdd = true
            while didAdd {
                didAdd = false
                for theme in project.themes where theme.parentID.map(result.contains) == true {
                    if result.insert(theme.id).inserted { didAdd = true }
                }
            }
            return result
        }()

        let visibleThemeIDs: Set<UUID>? = scopedThemeIDs.map { scopedIDs in
            var result = scopedIDs
            for id in scopedIDs {
                var parentID = themesByID[id]?.parentID
                while let current = parentID, result.insert(current).inserted {
                    parentID = themesByID[current]?.parentID
                }
            }
            return result
        }

        let themes = project.themes.filter { theme in
            visibleThemeIDs?.contains(theme.id) ?? true
        }.map { theme in
            ThemeContext(
                id: theme.id,
                name: theme.name,
                path: themePath(theme.id),
                parentID: theme.parentID,
                narrative: theme.note ?? ""
            )
        }

        var locators: [AnalysisEvidenceLocator] = []
        let scopedInterviews = project.interviews.filter { interview in
            scope.kind != .interview || interview.id == scope.interviewID
        }
        let contextRowCount = min(max(scope.surroundingRowCount, 0), 10)
        let evidence = scopedInterviews.flatMap { interview in
            let segmentsByID = Dictionary(uniqueKeysWithValues: interview.segments.map { ($0.id, $0) })
            let orderedSegments = interview.segments.sorted { $0.order < $1.order }
            return interview.codingUnits.filter { unit in
                guard let scopedThemeIDs else { return true }
                return !unit.themeIDs.isDisjoint(with: scopedThemeIDs)
            }.map { unit in
                let excerpt = unit.segmentIDs.compactMap { segmentsByID[$0] }
                    .sorted { $0.order < $1.order }
                    .map(\.text)
                    .joined(separator: " ")
                let selectedOrders = unit.segmentIDs.compactMap { segmentsByID[$0]?.order }
                let firstOrder = selectedOrders.min() ?? 0
                let lastOrder = selectedOrders.max() ?? firstOrder
                let preceding = orderedSegments.filter { $0.order < firstOrder }.suffix(contextRowCount)
                let following = orderedSegments.filter { $0.order > lastOrder }.prefix(contextRowCount)
                func transcriptContext(_ segment: TranscriptSegment) -> EvidenceContext.TranscriptContext {
                    .init(
                        order: segment.order,
                        speaker: segment.speaker,
                        start: segment.start,
                        end: segment.end,
                        text: segment.text
                    )
                }
                let evidenceID = stableEvidenceID(for: unit.id)
                locators.append(AnalysisEvidenceLocator(
                    evidenceID: evidenceID,
                    interviewID: interview.id,
                    codingUnitID: unit.id,
                    segmentIDs: unit.segmentIDs,
                    participant: interview.participant,
                    interview: interview.name,
                    excerpt: excerpt
                ))
                return EvidenceContext(
                    evidenceID: evidenceID,
                    interviewID: interview.id,
                    codingUnitID: unit.id,
                    segmentIDs: unit.segmentIDs,
                    participant: interview.participant,
                    interview: interview.name,
                    themePaths: unit.themeIDs.map(themePath).sorted(),
                    excerpt: excerpt,
                    memo: unit.memo,
                    precedingContext: preceding.map(transcriptContext),
                    followingContext: following.map(transcriptContext)
                )
            }
        }

        let scopeTitle: String = {
            switch scope.kind {
            case .project:
                return project.name
            case .interview:
                return project.interviews.first(where: { $0.id == scope.interviewID })?.name ?? project.name
            case .theme:
                guard let themeID = scope.themeID else { return project.name }
                return themePath(themeID)
            }
        }()

        let context = Context(
            project: project.name,
            generatedAt: .now,
            analysisBrief: brief,
            analysisScope: ScopeContext(
                kind: scope.kind.rawValue,
                title: scopeTitle,
                surroundingRowCount: contextRowCount
            ),
            participantCount: Set(scopedInterviews.map(\.participant)).count,
            interviewCount: scopedInterviews.count,
            transcriptRowCount: scopedInterviews.reduce(0) { $0 + $1.segments.count },
            codingUnitCount: evidence.count,
            themes: themes,
            codedEvidence: evidence
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return Snapshot(
            json: String(decoding: try encoder.encode(context), as: UTF8.self),
            evidence: locators
        )
    }

    static func stableEvidenceID(for codingUnitID: UUID) -> String {
        "E-" + codingUnitID.uuidString.replacingOccurrences(of: "-", with: "").prefix(12).uppercased()
    }
}
