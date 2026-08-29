import Foundation

struct ProjectLibraryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let folderName: String
    let createdAt: Date
    var updatedAt: Date
    var participantCount: Int?
    var codingUnitCount: Int?

    init(
        id: UUID = UUID(),
        name: String,
        folderName: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        participantCount: Int? = 0,
        codingUnitCount: Int? = 0
    ) {
        self.id = id
        self.name = name
        self.folderName = folderName ?? id.uuidString
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.participantCount = participantCount
        self.codingUnitCount = codingUnitCount
    }
}

struct ProjectLibraryIndex: Codable {
    var projects: [ProjectLibraryItem]
}
