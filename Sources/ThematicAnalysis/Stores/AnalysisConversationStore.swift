import Combine
import Foundation

@MainActor
final class AnalysisConversationStore: ObservableObject {
    @Published private(set) var conversations: [AnalysisConversation] = []
    @Published var selectedConversationID: UUID?
    @Published private(set) var persistenceError = ""

    private struct Archive: Codable {
        var selectedConversationID: UUID?
        var conversations: [AnalysisConversation]
    }

    private let fileManager: FileManager
    private let archiveURL: URL

    init(storageRoot: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let directory = storageRoot.appendingPathComponent("AnalizAsistani", isDirectory: true)
        archiveURL = directory.appendingPathComponent("konusmalar.json")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
        if conversations.isEmpty {
            _ = createConversation()
        }
    }

    var selectedConversation: AnalysisConversation? {
        guard let selectedConversationID else { return nil }
        return conversations.first { $0.id == selectedConversationID }
    }

    var selectedMessages: [AnalysisChatMessage] {
        selectedConversation?.messages ?? []
    }

    var sortedConversations: [AnalysisConversation] {
        conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func createConversation() -> UUID {
        let conversation = AnalysisConversation(title: AppLocalization.string("Yeni konuşma"))
        conversations.append(conversation)
        selectedConversationID = conversation.id
        persist()
        return conversation.id
    }

    func select(_ id: UUID) {
        guard conversations.contains(where: { $0.id == id }) else { return }
        selectedConversationID = id
        persist()
    }

    func append(_ message: AnalysisChatMessage, to conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].messages.append(message)
        conversations[index].updatedAt = .now
        if message.role == .user, conversations[index].messages.filter({ $0.role == .user }).count == 1 {
            conversations[index].title = Self.title(for: message)
        }
        persist()
    }

    func setReviewDecision(_ decision: AnalysisReviewDecision?, messageID: UUID, conversationID: UUID) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        conversations[conversationIndex].messages[messageIndex].reviewDecision = decision
        conversations[conversationIndex].updatedAt = .now
        persist()
    }

    func rename(_ id: UUID, to title: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty,
              let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].title = cleanTitle
        conversations[index].updatedAt = .now
        persist()
    }

    func clear(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].messages = []
        conversations[index].title = AppLocalization.string("Yeni konuşma")
        conversations[index].updatedAt = .now
        persist()
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if conversations.isEmpty {
            _ = createConversation()
            return
        }
        if selectedConversationID == id {
            selectedConversationID = sortedConversations.first?.id
        }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: archiveURL),
              let archive = try? JSONDecoder.tematik.decode(Archive.self, from: data) else { return }
        conversations = archive.conversations
        selectedConversationID = archive.selectedConversationID.flatMap { selectedID in
            conversations.contains(where: { $0.id == selectedID }) ? selectedID : nil
        } ?? conversations.sorted { $0.updatedAt > $1.updatedAt }.first?.id
    }

    private func persist() {
        do {
            let archive = Archive(
                selectedConversationID: selectedConversationID,
                conversations: conversations
            )
            try JSONEncoder.tematik.encode(archive).write(to: archiveURL, options: .atomic)
            persistenceError = ""
        } catch {
            persistenceError = AppLocalization.string("Konuşmalar kaydedilemedi: ") + error.localizedDescription
        }
    }

    private static func title(for message: AnalysisChatMessage) -> String {
        let cleanText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = cleanText.isEmpty ? (message.attachments.first?.filename ?? AppLocalization.string("Yeni konuşma")) : cleanText
        let maximumLength = 52
        guard source.count > maximumLength else { return source }
        return String(source.prefix(maximumLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
