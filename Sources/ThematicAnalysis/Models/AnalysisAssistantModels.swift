import Foundation

enum AnalysisMethodProfile: String, Codable, CaseIterable, Identifiable {
    case general
    case reflexive
    case codebook
    case framework
    case codingReliability = "coding_reliability"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: AppLocalization.string("Verilerle konuş")
        case .reflexive: AppLocalization.string("Refleksif tematik analiz")
        case .codebook: AppLocalization.string("Kod kitabı tematik analizi")
        case .framework: AppLocalization.string("Framework analizi")
        case .codingReliability: AppLocalization.string("Kodlama güvenilirliği yaklaşımı")
        }
    }

    var resourceName: String {
        switch self {
        case .general: "AnalysisMethod-General"
        case .reflexive: "AnalysisMethod-ReflexiveTA"
        case .codebook: "AnalysisMethod-CodebookTA"
        case .framework: "AnalysisMethod-Framework"
        case .codingReliability: "AnalysisMethod-CodingReliability"
        }
    }

    var fallbackInstructions: String {
        switch self {
        case .general:
            "Belirli bir analiz yöntemini varsayma. Kullanıcının sorusunu sağlanan araştırma verisiyle yanıtla; kanıt, yorum ve yöntem önerisini birbirinden ayır."
        case .reflexive:
            "AI yorumlayıcı otorite değildir. Temaları veri içinde hazır bulunan nesneler gibi sunma; araştırmacının geliştirdiği merkezi anlam örüntüleri olarak ele al. Alternatif okumaları ve refleksif soruları görünür kıl."
        case .codebook:
            "Kod kitabındaki tanım, dahil etme ve hariç tutma ölçütlerini tutarlı uygula. Yeni kodları mevcut kodlardan açıkça ayır ve kod kitabı değişikliklerini yalnızca öneri olarak sun."
        case .framework:
            "Vakalar ile analitik kategoriler arasındaki matrisi koru. Hücre özetlerini kanıta bağla; vaka içi bağlamı frekanslara indirgeme ve boş hücreleri veri yokluğu olarak açıkça işaretle."
        case .codingReliability:
            "Kodlama birimini ve karar kurallarını sabit tut. Belirsiz ve sınırda örnekleri işaretle; uyum ölçülerini yorumun doğruluğuyla eşitleme ve araştırmacı kararını nihai say."
        }
    }

    var instructions: String {
        let url = Bundle.module.url(forResource: resourceName, withExtension: "md")
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? fallbackInstructions
    }
}

struct AnalysisBrief: Codable, Equatable {
    var researchQuestion = ""
    var theoreticalApproach = ""
    var researcherPosition = ""
    var analysisUnit = ""
    var exclusions = ""

    var isEmpty: Bool {
        [researchQuestion, theoreticalApproach, researcherPosition, analysisUnit, exclusions]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct AnalysisAssistantScope: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case project
        case interview
        case theme

        var id: String { rawValue }
    }

    var kind: Kind = .project
    var interviewID: UUID?
    var themeID: UUID?
    var surroundingRowCount = 2

    static let project = AnalysisAssistantScope()
}

enum AnalysisReviewDecision: String, Codable, CaseIterable, Identifiable {
    case accepted
    case revise
    case rejected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accepted: AppLocalization.string("Kabul edildi")
        case .revise: AppLocalization.string("Revize edilecek")
        case .rejected: AppLocalization.string("Reddedildi")
        }
    }

    var symbol: String {
        switch self {
        case .accepted: "checkmark.circle"
        case .revise: "pencil.circle"
        case .rejected: "xmark.circle"
        }
    }
}

struct AnalysisEvidenceLocator: Codable, Equatable, Identifiable {
    let evidenceID: String
    let interviewID: UUID
    let codingUnitID: UUID
    let segmentIDs: [UUID]
    let participant: String
    let interview: String
    let excerpt: String

    var id: String { evidenceID }
}

struct AnalysisRunProvenance: Codable, Equatable {
    static let promptVersion = "3.0"

    let modelID: String
    let methodProfileID: String
    let promptVersion: String
    let createdAt: Date
    let evidenceScopeIDs: [String]
}

struct AnalysisFileAttachment: Identifiable, Codable, Equatable {
    static let maximumRequestBytes = 50 * 1_024 * 1_024

    let id: UUID
    let filename: String
    let mimeType: String
    let data: Data

    var byteCount: Int { data.count }
    var isPDF: Bool { filename.lowercased().hasSuffix(".pdf") }

    init(id: UUID = UUID(), filename: String, mimeType: String, data: Data) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}

struct AnalysisAssistantResponse: Codable, Equatable {
    struct EvidenceReference: Codable, Equatable, Identifiable {
        let evidenceID: String
        let claim: String

        var id: String { "\(evidenceID)|\(claim)" }

        private enum CodingKeys: String, CodingKey {
            case evidenceID = "evidence_id"
            case claim
        }
    }

    struct Block: Codable, Equatable, Identifiable {
        enum Kind: String, Codable {
            case paragraph
            case bullets
            case table
            case barChart = "bar_chart"
        }

        struct TableRow: Codable, Equatable, Identifiable {
            let cells: [String]
            var id: String { cells.joined(separator: "\u{1F}") }
        }

        struct ChartItem: Codable, Equatable, Identifiable {
            let label: String
            let value: Double
            var id: String { label }
        }

        let kind: Kind
        let title: String
        let text: String
        let items: [String]
        let columns: [String]
        let rows: [TableRow]
        let chart: [ChartItem]

        var id: String {
            "\(kind.rawValue)|\(title)|\(text.prefix(48))|\(items.count)|\(rows.count)|\(chart.count)"
        }
    }

    let title: String
    let blocks: [Block]
    let followUpQuestions: [String]
    let evidenceReferences: [EvidenceReference]

    init(
        title: String,
        blocks: [Block],
        followUpQuestions: [String],
        evidenceReferences: [EvidenceReference] = []
    ) {
        self.title = title
        self.blocks = blocks
        self.followUpQuestions = followUpQuestions
        self.evidenceReferences = evidenceReferences
    }

    private enum CodingKeys: String, CodingKey {
        case title, blocks
        case followUpQuestions = "follow_up_questions"
        case evidenceReferences = "evidence_references"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decode(String.self, forKey: .title)
        blocks = try values.decode([Block].self, forKey: .blocks)
        followUpQuestions = try values.decodeIfPresent([String].self, forKey: .followUpQuestions) ?? []
        evidenceReferences = try values.decodeIfPresent([EvidenceReference].self, forKey: .evidenceReferences) ?? []
    }
}

struct AnalysisChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable, Equatable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String
    let response: AnalysisAssistantResponse?
    let attachments: [AnalysisFileAttachment]
    let provenance: AnalysisRunProvenance?
    var reviewDecision: AnalysisReviewDecision?

    static func user(_ text: String, attachments: [AnalysisFileAttachment] = []) -> Self {
        Self(id: UUID(), role: .user, text: text, response: nil, attachments: attachments, provenance: nil, reviewDecision: nil)
    }

    static func assistant(_ response: AnalysisAssistantResponse, provenance: AnalysisRunProvenance? = nil) -> Self {
        Self(id: UUID(), role: .assistant, text: "", response: response, attachments: [], provenance: provenance, reviewDecision: nil)
    }
}

struct AnalysisConversation: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [AnalysisChatMessage]

    init(
        id: UUID = UUID(),
        title: String = "Yeni konuşma",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        messages: [AnalysisChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

struct OpenAIAnalysisModel: Codable, Identifiable, Equatable {
    let id: String
    let created: Int?
    let ownedBy: String?

    private enum CodingKeys: String, CodingKey {
        case id, created
        case ownedBy = "owned_by"
    }
}
