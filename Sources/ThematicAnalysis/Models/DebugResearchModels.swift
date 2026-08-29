import Foundation

enum DebugLabModule: String, CaseIterable, Identifiable {
    case profile
    case frequency
    case milesMatrix
    case prevalence
    case frameworkMatrix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: "Theme Dominance"
        case .frequency: "Content Analysis"
        case .milesMatrix: "Miles–Huberman Matrix"
        case .prevalence: "Participant Prevalence"
        case .frameworkMatrix: "Framework Matrix"
        }
    }

    var subtitle: String {
        switch self {
        case .profile: "Compare frequency, participant reach, and case intensity."
        case .frequency: "Review coding frequency and its share of the dataset."
        case .milesMatrix: "Compare participants across themes on a 0–2 scale."
        case .prevalence: "See how many participants contribute evidence to each theme."
        case .frameworkMatrix: "Review analytic summaries and evidence by participant and theme."
        }
    }
}

enum DebugCodeStatus: String, CaseIterable, Identifiable {
    case draft = "Draft"
    case active = "Active"
    case review = "Review"
    case retired = "Retired"

    var id: String { rawValue }
}

struct DebugCodebookEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let parentID: String?
    let status: DebugCodeStatus
    let definition: String
    let includeWhen: String
    let excludeWhen: String
    let example: String
    let revision: Int
    let colorIndex: Int
}

struct DebugResearchParticipant: Identifiable, Hashable {
    let id: String
    let name: String
    let role: String
    let usageGroup: String
}

struct DebugResearchExcerpt: Identifiable, Hashable {
    let id: String
    let participantID: String
    let time: String
    let text: String
    let codeIDs: Set<String>
    let analyticMemo: String
}

enum DebugThemeStage: String, CaseIterable, Identifiable {
    case candidate = "Candidate"
    case review = "In Review"
    case final = "Final"

    var id: String { rawValue }
}

struct DebugCandidateTheme: Identifiable, Hashable {
    let id: String
    let title: String
    let stage: DebugThemeStage
    let centralConcept: String
    let scope: String
    let codeIDs: [String]
    let evidenceIDs: [String]
    let contradictoryEvidenceIDs: [String]
    let analyticNarrative: String
    let frameworkSummaries: [String: String]
    let colorIndex: Int
}

enum DebugJournalPhase: String, CaseIterable, Identifiable {
    case familiarization = "Familiarization"
    case coding = "Coding"
    case themeDevelopment = "Theme Development"
    case review = "Theme Review"
    case reporting = "Reporting"

    var id: String { rawValue }
}

struct DebugJournalEntry: Identifiable, Hashable {
    let id: String
    let date: Date
    let phase: DebugJournalPhase
    let title: String
    let reflection: String
    let decision: String
    let linkedThemeIDs: [String]
    let linkedExcerptIDs: [String]
}

enum DebugQueryOperator: String, CaseIterable, Identifiable {
    case and = "Both (AND)"
    case or = "At Least One (OR)"
    case without = "First Without Second (NOT)"

    var id: String { rawValue }
}

struct DebugResearchDataset {
    let participants: [DebugResearchParticipant]
    let codebook: [DebugCodebookEntry]
    let excerpts: [DebugResearchExcerpt]
    let candidateThemes: [DebugCandidateTheme]
    let journal: [DebugJournalEntry]

    func participant(_ id: String) -> DebugResearchParticipant? {
        participants.first { $0.id == id }
    }

    func code(_ id: String) -> DebugCodebookEntry? {
        codebook.first { $0.id == id }
    }

    func excerpt(_ id: String) -> DebugResearchExcerpt? {
        excerpts.first { $0.id == id }
    }

    func excerpts(for candidate: DebugCandidateTheme, participantID: String? = nil) -> [DebugResearchExcerpt] {
        let evidence = Set(candidate.evidenceIDs + candidate.contradictoryEvidenceIDs)
        return excerpts.filter { excerpt in
            evidence.contains(excerpt.id) && (participantID == nil || excerpt.participantID == participantID)
        }
    }

    func query(
        firstCodeID: String,
        secondCodeID: String,
        operator queryOperator: DebugQueryOperator,
        usageGroup: String?
    ) -> [DebugResearchExcerpt] {
        excerpts.filter { excerpt in
            let matchesGroup = usageGroup == nil || participant(excerpt.participantID)?.usageGroup == usageGroup
            let hasFirst = excerpt.codeIDs.contains(firstCodeID)
            let hasSecond = excerpt.codeIDs.contains(secondCodeID)
            let matchesCodes: Bool
            switch queryOperator {
            case .and: matchesCodes = hasFirst && hasSecond
            case .or: matchesCodes = hasFirst || hasSecond
            case .without: matchesCodes = hasFirst && !hasSecond
            }
            return matchesGroup && matchesCodes
        }
    }
}
