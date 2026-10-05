import Foundation

enum DebugLabModule: String, CaseIterable, Identifiable {
    case overview
    case profile
    case frequency
    case milesMatrix
    case prevalence
    case codebook
    case themeWorkbench
    case queries
    case journal
    case evidenceReport
    case frameworkMatrix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Debug Analiz Laboratuvarı"
        case .profile: "Tema Baskınlık Profili"
        case .frequency: "Nitel İçerik Analizi"
        case .milesMatrix: "Miles–Huberman Matrisi"
        case .prevalence: "Katılımcı Yaygınlığı"
        case .codebook: "Kod Kitabı"
        case .themeWorkbench: "Tema Geliştirme Masası"
        case .queries: "Karşılaştırma ve Sorgu"
        case .journal: "Refleksif Araştırma Günlüğü"
        case .evidenceReport: "Kanıta Bağlı Rapor"
        case .frameworkMatrix: "Framework Matrix"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "Deneysel yöntemleri tek tek inceleyin; bu alan proje verisini değiştirmez."
        case .profile: "Frekans, katılımcı erişimi ve vaka yoğunluğunu birlikte okuyun."
        case .frequency: "Kodlama görünümü ve toplam içindeki payı betimsel olarak karşılaştırın."
        case .milesMatrix: "Katılımcıları kavramsal temalara göre 0–2 gösterimle karşılaştırın."
        case .prevalence: "Bir temanın kaç farklı katılımcının verisinde görüldüğünü inceleyin."
        case .codebook: "Kod tanımlarını, sınırlarını, örneklerini ve sürüm durumunu değerlendirin."
        case .themeWorkbench: "Kodlardan aday temalara, gözden geçirmeden nihai temaya ilerleyin."
        case .queries: "Kod birlikteliklerini ve katılımcı gruplarını mantıksal sorgularla karşılaştırın."
        case .journal: "Analitik kararları, tereddütleri ve araştırmacı konumunu zaman içinde izleyin."
        case .evidenceReport: "Tema anlatısını destekleyen ve sınırlandıran kanıtlarla birlikte okuyun."
        case .frameworkMatrix: "Katılımcı × tema hücrelerinde analitik özetleri ve dayanak alıntıları inceleyin."
        }
    }
}

enum DebugCodeStatus: String, CaseIterable, Identifiable {
    case draft = "Taslak"
    case active = "Etkin"
    case review = "Gözden geçir"
    case retired = "Arşiv"

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
    case candidate = "Aday"
    case review = "Gözden geçiriliyor"
    case final = "Nihai"

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
    case familiarization = "Veriye aşinalık"
    case coding = "Kodlama"
    case themeDevelopment = "Tema geliştirme"
    case review = "Tema gözden geçirme"
    case reporting = "Raporlama"

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
    case and = "İkisi de (AND)"
    case or = "En az biri (OR)"
    case without = "Birinci var, ikinci yok (NOT)"

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
