import Charts
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AnalysisAssistantViewModel: ObservableObject {
    @Published private(set) var isSending = false
    @Published var errorMessage = ""

    func send(
        question: String,
        attachments: [AnalysisFileAttachment],
        project: AnalysisProject,
        brief: AnalysisBrief,
        scope: AnalysisAssistantScope,
        methodProfile: AnalysisMethodProfile,
        storageRoot: URL,
        model: String,
        conversationStore: AnalysisConversationStore
    ) async {
        let cleanQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuestion.isEmpty || !attachments.isEmpty,
              !isSending,
              let conversationID = conversationStore.selectedConversationID else { return }

        let apiKey = OpenAIAPIKeyStore.load()
        guard !apiKey.isEmpty else {
            errorMessage = AppLocalization.string("OpenAI API anahtarı girilmedi.")
            return
        }

        let displayedQuestion = cleanQuestion.isEmpty
            ? AppLocalization.string("Ekli dosyaları tematik analiz bağlamında incele.")
            : cleanQuestion
        conversationStore.append(.user(displayedQuestion, attachments: attachments), to: conversationID)
        isSending = true
        errorMessage = ""
        defer { isSending = false }

        do {
            let context = try AnalysisAssistantContextBuilder.makeSnapshot(
                from: project,
                brief: brief,
                scope: scope
            )
            let response = try await OpenAIAnalysisAssistantService.respond(
                apiKey: apiKey,
                configuration: .load(modelID: model),
                projectContext: context.json,
                methodProfile: methodProfile,
                validEvidenceIDs: context.evidenceIDs,
                messages: conversationStore.conversations.first(where: { $0.id == conversationID })?.messages ?? []
            )
            let provenance = AnalysisRunProvenance(
                modelID: model,
                methodProfileID: methodProfile.rawValue,
                promptVersion: AnalysisRunProvenance.promptVersion,
                createdAt: .now,
                evidenceScopeIDs: context.evidence.map(\.evidenceID).sorted()
            )
            let message = AnalysisChatMessage.assistant(response, provenance: provenance)
            conversationStore.append(message, to: conversationID)
            do {
                try AnalysisAssistantArtifactStore.appendAudit(
                    event: .responseGenerated,
                    conversationID: conversationID,
                    messageID: message.id,
                    response: response,
                    provenance: provenance,
                    storageRoot: storageRoot
                )
            } catch {
                errorMessage = AppLocalization.string("Yanıt alındı ancak denetim kaydı yazılamadı: ") + error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AnalysisAssistantView: View {
    @ObservedObject var store: AnalysisStore
    @ObservedObject var workspaceStore: AnalysisAssistantWorkspaceStore
    let onOpenContext: () -> Void
    let onOpenEvidence: (AnalysisEvidenceLocator) -> Void
    @AppStorage("hasOpenAIAPIKey") private var hasOpenAIAPIKey = false
    @AppStorage("openAIAnalysisModel") private var selectedModel = AnalysisModelCatalog.defaultModelID
    @SceneStorage("analysisAssistantShowsHistory") private var showsConversationSidebar = true
    @StateObject private var conversationStore: AnalysisConversationStore
    @StateObject private var viewModel = AnalysisAssistantViewModel()
    @State private var draft = ""
    @State private var attachments: [AnalysisFileAttachment] = []
    @State private var isImportingFiles = false
    @State private var attachmentError = ""
    @State private var renameDraft = ""
    @State private var conversationToRename: UUID?
    @State private var conversationToDelete: UUID?
    @FocusState private var composerFocused: Bool

    init(
        store: AnalysisStore,
        workspaceStore: AnalysisAssistantWorkspaceStore,
        onOpenContext: @escaping () -> Void = {},
        onOpenEvidence: @escaping (AnalysisEvidenceLocator) -> Void = { _ in }
    ) {
        self.store = store
        self.workspaceStore = workspaceStore
        self.onOpenContext = onOpenContext
        self.onOpenEvidence = onOpenEvidence
        _conversationStore = StateObject(
            wrappedValue: AnalysisConversationStore(storageRoot: store.storageRoot)
        )
    }

    private let suggestions = [
        "Seçili kapsamı önce betimle; yorum ile doğrudan kanıtı birbirinden ayır.",
        "Bir aday temayı merkezi fikir, kapsam ve sınırlar açısından gözden geçir.",
        "Destekleyen, sınırlandıran ve çelişen kanıtları birlikte göster.",
        "Önce tekil vakaları incele, ardından vakalar arası örüntüleri karşılaştır.",
        "Kod ile tema arasındaki olası uyumsuzlukları kaynağa dönerek incele.",
        "Bu analiz için refleksif bir araştırmacı notu ve takip soruları oluştur."
    ]

    private var hasDefinedAnalysisContext: Bool {
        !workspaceStore.brief.isEmpty || workspaceStore.scope.kind != .project
    }

    private var evidenceByID: [String: AnalysisEvidenceLocator] {
        let evidence = (try? AnalysisAssistantContextBuilder.makeSnapshot(from: store.project).evidence) ?? []
        return Dictionary(uniqueKeysWithValues: evidence.map { ($0.evidenceID, $0) })
    }

    var body: some View {
        HSplitView {
            if showsConversationSidebar {
                conversationSidebar
                    .frame(minWidth: 170, idealWidth: 220, maxWidth: 340)
            }
            assistantDetail
                .frame(minWidth: 560)
        }
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task { await addAttachments(from: urls) }
            case let .failure(error):
                attachmentError = error.localizedDescription
            }
        }
        .onAppear {
            hasOpenAIAPIKey = !OpenAIAPIKeyStore.load().isEmpty
            workspaceStore.normalize(for: store.project)
        }
        .onChange(of: conversationStore.selectedConversationID) {
            if let id = conversationStore.selectedConversationID {
                conversationStore.select(id)
            }
            attachments = []
            attachmentError = ""
            viewModel.errorMessage = ""
        }
        .alert("Konuşmayı yeniden adlandır", isPresented: Binding(
            get: { conversationToRename != nil },
            set: { if !$0 { conversationToRename = nil } }
        )) {
            TextField("Konuşma adı", text: $renameDraft)
            Button("Vazgeç", role: .cancel) { conversationToRename = nil }
            Button("Kaydet") {
                if let id = conversationToRename { conversationStore.rename(id, to: renameDraft) }
                conversationToRename = nil
            }
        }
        .alert("Konuşma silinsin mi?", isPresented: Binding(
            get: { conversationToDelete != nil },
            set: { if !$0 { conversationToDelete = nil } }
        )) {
            Button("Vazgeç", role: .cancel) { conversationToDelete = nil }
            Button("Sil", role: .destructive) {
                if let id = conversationToDelete { conversationStore.delete(id) }
                conversationToDelete = nil
            }
        } message: {
            Text("Bu konuşma ve ekli dosyaları kalıcı olarak silinecek.")
        }
    }

    private var assistantDetail: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if !hasOpenAIAPIKey {
                missingKeyView
            } else {
                conversation
                Divider()
                composer
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var conversationSidebar: some View {
        VStack(spacing: 0) {
            Button {
                _ = conversationStore.createConversation()
                draft = ""
                attachments = []
                composerFocused = true
            } label: {
                Label("Yeni konuşma", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(12)
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            List(selection: $conversationStore.selectedConversationID) {
                ForEach(conversationStore.sortedConversations) { item in
                    ConversationRow(conversation: item)
                        .tag(item.id)
                        .contextMenu {
                            Button("Yeniden Adlandır…") { beginRenaming(item) }
                            Button("Sil", role: .destructive) { conversationToDelete = item.id }
                        }
                }
            }
            .listStyle(.sidebar)

            if !conversationStore.persistenceError.isEmpty {
                Label(conversationStore.persistenceError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(10)
            }
        }
        .background(.bar)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsConversationSidebar.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help(showsConversationSidebar ? "Konuşma geçmişini gizle" : "Konuşma geçmişini göster")

            VStack(alignment: .leading, spacing: 3) {
                Text("Analiz Asistanı")
                    .font(.title2.weight(.semibold))
                Text("Tema, anlatı, kodlanmış alıntı ve memolar üzerine proje bağlamında konuşun.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Yöntem", selection: Binding(
                get: { store.analysisMethodProfile },
                set: { store.updateAnalysisMethodProfile($0) }
            )) {
                ForEach(AnalysisMethodProfile.allCases) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 210)
            .help("Yanıtta uygulanacak analiz yaklaşımı; Verilerle konuş belirli bir yöntem varsaymaz")
            if let active = conversationStore.selectedConversation {
                Menu {
                    Button("Yeniden Adlandır…") { beginRenaming(active) }
                    Button("Sohbeti Temizle", systemImage: "eraser", role: .destructive) {
                        conversationStore.clear(active.id)
                        attachments = []
                        attachmentError = ""
                    }
                    Divider()
                    SettingsLink {
                        Label("Model Ayarları", systemImage: "slider.horizontal.3")
                    }
                    Divider()
                    Button("Konuşmayı Sil", systemImage: "trash", role: .destructive) {
                        conversationToDelete = active.id
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.small)
                .help("Konuşma seçenekleri")
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var missingKeyView: some View {
        ContentUnavailableView {
            Label("OpenAI API anahtarı gerekli", systemImage: "key")
        } description: {
            Text("Analiz asistanı, Ayarlar’da güvenli biçimde saklanan API anahtarını kullanır.")
        } actions: {
            SettingsLink {
                Text("Ayarları Aç")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if conversationStore.selectedMessages.isEmpty {
                        welcome
                    }

                    ForEach(conversationStore.selectedMessages) { message in
                        ChatMessageView(
                            message: message,
                            evidenceByID: evidenceByID,
                            onOpenEvidence: onOpenEvidence,
                            onSaveMemo: { saveMemo(for: message) },
                            onFollowUp: submitSuggestion,
                            onReview: { decision in
                                guard let conversationID = conversationStore.selectedConversationID else { return }
                                conversationStore.setReviewDecision(
                                    decision,
                                    messageID: message.id,
                                    conversationID: conversationID
                                )
                            }
                        )
                            .id(message.id)
                    }

                    if viewModel.isSending {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Analiz ediliyor…")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .id("assistant-progress")
                    }

                    if !viewModel.errorMessage.isEmpty {
                        Label(viewModel.errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .padding(12)
                            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .frame(maxWidth: 920)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: conversationStore.selectedMessages.count) {
                guard let last = conversationStore.selectedMessages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: viewModel.isSending) {
                if viewModel.isSending {
                    withAnimation { proxy.scrollTo("assistant-progress", anchor: .bottom) }
                }
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Tematik analizinizi birlikte yorumlayalım", systemImage: "sparkles")
                .font(.title3.weight(.semibold))
            Text("Asistan yalnızca bu projedeki analiz bağlamını kullanır. Kanıtın yetmediği durumları ayrıca belirtmesi istenir.")
                .foregroundStyle(.secondary)
            if !hasDefinedAnalysisContext {
                HStack(spacing: 6) {
                    Text("Daha odaklı yanıtlar için Analiz Asistanı altındaki Bağlam bölümünü doldurun.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Bağlamı Aç", action: onOpenContext)
                        .buttonStyle(.link)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                ForEach(suggestions, id: \.self) { suggestion in
                    let localizedSuggestion = AppLocalization.string(suggestion)
                    Button {
                        submitSuggestion(localizedSuggestion)
                    } label: {
                        HStack(alignment: .top) {
                            Text(verbatim: localizedSuggestion)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .buttonStyle(.plain)
                    .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.07)))
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            AttachmentChip(attachment: attachment) {
                                attachments.removeAll { $0.id == attachment.id }
                                attachmentError = ""
                            }
                        }
                    }
                }
            }

            if !attachmentError.isEmpty {
                Label(attachmentError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    isImportingFiles = true
                } label: {
                    Image(systemName: "paperclip")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered)
                .help("Dosya ekle")
                .disabled(viewModel.isSending)

                TextField("Tematik analiz hakkında bir soru sorun…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .onSubmit(submit)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))

                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .disabled(
                    (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
                        || viewModel.isSending
                )
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Gönder (⌘↩)")
            }

        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func submit() {
        performSubmit(question: draft)
    }

    private func submitSuggestion(_ suggestion: String) {
        performSubmit(question: suggestion)
    }

    private func performSubmit(question rawQuestion: String) {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty || !attachments.isEmpty, !viewModel.isSending else { return }
        let submittedAttachments = attachments
        draft = ""
        attachments = []
        attachmentError = ""
        Task {
            await viewModel.send(
                question: question,
                attachments: submittedAttachments,
                project: store.project,
                brief: workspaceStore.brief,
                scope: workspaceStore.scope,
                methodProfile: store.analysisMethodProfile,
                storageRoot: store.storageRoot,
                model: selectedModel,
                conversationStore: conversationStore
            )
            composerFocused = true
        }
    }

    @MainActor
    private func addAttachments(from urls: [URL]) async {
        attachmentError = ""
        do {
            let existingBytes = conversationStore.selectedMessages.flatMap(\.attachments).reduce(0) { $0 + $1.byteCount }
                + attachments.reduce(0) { $0 + $1.byteCount }
            let loaded = try await AnalysisAttachmentLoader.load(urls: urls, existingBytes: existingBytes)
            attachments.append(contentsOf: loaded)
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    private func beginRenaming(_ conversation: AnalysisConversation) {
        renameDraft = conversation.title
        conversationToRename = conversation.id
    }

    private func saveMemo(for message: AnalysisChatMessage) {
        guard let response = message.response,
              let provenance = message.provenance,
              let conversationID = conversationStore.selectedConversationID else { return }
        do {
            let url = try AnalysisAssistantArtifactStore.saveMemo(
                response: response,
                provenance: provenance,
                storageRoot: store.storageRoot
            )
            try AnalysisAssistantArtifactStore.appendAudit(
                event: .memoSaved,
                conversationID: conversationID,
                messageID: message.id,
                response: response,
                provenance: provenance,
                artifactPath: url.path,
                storageRoot: store.storageRoot
            )
            store.lastMessage = "Analiz notu kaydedildi: \(url.lastPathComponent)"
        } catch {
            viewModel.errorMessage = AppLocalization.string("Analiz notu kaydedilemedi: ") + error.localizedDescription
        }
    }
}

private struct ConversationRow: View {
    let conversation: AnalysisConversation

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "bubble.left")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(verbatim: conversation.updatedAt.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .shortened)
                        .locale(AppLocalization.language.locale)
                ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct AttachmentChip: View {
    let attachment: AnalysisFileAttachment
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: attachment.isPDF ? "doc.richtext" : "doc")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.filename)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.string("Dosyayı kaldır"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(nsColor: .separatorColor)))
    }
}

private struct ChatMessageView: View {
    let message: AnalysisChatMessage
    let evidenceByID: [String: AnalysisEvidenceLocator]
    let onOpenEvidence: (AnalysisEvidenceLocator) -> Void
    let onSaveMemo: () -> Void
    let onFollowUp: (String) -> Void
    let onReview: (AnalysisReviewDecision?) -> Void

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 90)
                VStack(alignment: .leading, spacing: 8) {
                    if !message.text.isEmpty {
                        Text(message.text)
                            .textSelection(.enabled)
                    }
                    ForEach(message.attachments) { attachment in
                        Label {
                            Text(attachment.filename).lineLimit(1)
                        } icon: {
                            Image(systemName: attachment.isPDF ? "doc.richtext" : "doc")
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
        case .assistant:
            if let response = message.response {
                AssistantResponseView(
                    response: response,
                    provenance: message.provenance,
                    reviewDecision: message.reviewDecision,
                    evidenceByID: evidenceByID,
                    onOpenEvidence: onOpenEvidence,
                    onSaveMemo: onSaveMemo,
                    onFollowUp: onFollowUp,
                    onReview: onReview
                )
            }
        }
    }
}

private struct AssistantResponseView: View {
    let response: AnalysisAssistantResponse
    let provenance: AnalysisRunProvenance?
    let reviewDecision: AnalysisReviewDecision?
    let evidenceByID: [String: AnalysisEvidenceLocator]
    let onOpenEvidence: (AnalysisEvidenceLocator) -> Void
    let onSaveMemo: () -> Void
    let onFollowUp: (String) -> Void
    let onReview: (AnalysisReviewDecision?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                Text(response.title)
                    .font(.headline)
            }

            ForEach(response.blocks) { block in
                AnalysisResponseBlockView(block: block)
            }

            if !response.evidenceReferences.isEmpty {
                Divider()
                Text("Doğrulanmış kanıt bağlantıları")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(response.evidenceReferences) { reference in
                    if let evidence = evidenceByID[reference.evidenceID] {
                        Button {
                            onOpenEvidence(evidence)
                        } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(reference.claim)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Text("\(reference.evidenceID) · \(evidence.participant) · \(evidence.interview)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help("Kanıtı transkriptte aç")
                    }
                }
            }

            if !response.followUpQuestions.isEmpty {
                Divider()
                Text("Devam edebileceğiniz sorular")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(response.followUpQuestions, id: \.self) { question in
                    Button {
                        onFollowUp(question)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Image(systemName: "arrow.turn.down.right")
                                .foregroundStyle(.tint)
                            Text(question)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Bu soruyla devam et")
                }
            }

            if let provenance {
                Divider()
                HStack(spacing: 10) {
                    Label(
                        "\(provenance.modelID) · \(provenance.methodProfileID) · \(AppLocalization.string("istem")) \(provenance.promptVersion)",
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(AnalysisReviewDecision.allCases) { decision in
                            Button {
                                onReview(decision)
                            } label: {
                                Label(decision.title, systemImage: decision.symbol)
                            }
                        }
                        if reviewDecision != nil {
                            Divider()
                            Button("Kararı kaldır") { onReview(nil) }
                        }
                    } label: {
                        Label(
                            reviewDecision?.title ?? AppLocalization.string("Araştırmacı kararı"),
                            systemImage: reviewDecision?.symbol ?? "person.crop.circle.badge.checkmark"
                        )
                    }
                    .controlSize(.small)
                    Button(action: onSaveMemo) {
                        Label("Memo olarak kaydet", systemImage: "square.and.arrow.down")
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.08)))
        .textSelection(.enabled)
    }

}

private struct AnalysisResponseBlockView: View {
    let block: AnalysisAssistantResponse.Block

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !block.title.isEmpty {
                Text(block.title)
                    .font(.subheadline.weight(.semibold))
            }

            switch block.kind {
            case .paragraph:
                Text(markdown: block.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .bullets:
                ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().frame(width: 5, height: 5)
                        Text(markdown: item)
                    }
                }
            case .table:
                AnalysisTableView(columns: block.columns, rows: block.rows)
            case .barChart:
                if !block.chart.isEmpty {
                    Chart(block.chart) { item in
                        BarMark(
                            x: .value("Değer", item.value),
                            y: .value("Kategori", item.label)
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                        .annotation(position: .trailing) {
                            Text(item.value.formatted(.number.precision(.fractionLength(0...2))))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxisLabel("Değer")
                    .frame(minHeight: 180, idealHeight: CGFloat(block.chart.count * 34 + 50), maxHeight: 420)
                    .padding(10)
                    .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

private struct AnalysisTableView: View {
    let columns: [String]
    let rows: [AnalysisAssistantResponse.Block.TableRow]

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        Text(column)
                            .font(.caption.weight(.semibold))
                            .padding(9)
                            .frame(minWidth: 120, maxWidth: 260, alignment: .leading)
                            .background(.quaternary)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(columns.indices, id: \.self) { columnIndex in
                            Text(row.cells.indices.contains(columnIndex) ? row.cells[columnIndex] : "")
                                .font(.callout)
                                .padding(9)
                                .frame(minWidth: 120, maxWidth: 260, alignment: .leading)
                                .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.05))
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private extension Text {
    init(markdown: String) {
        if let attributed = try? AttributedString(markdown: markdown) {
            self.init(attributed)
        } else {
            self.init(verbatim: markdown)
        }
    }
}
