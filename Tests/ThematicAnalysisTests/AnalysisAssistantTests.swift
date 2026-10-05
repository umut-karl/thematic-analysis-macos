import Foundation
import XCTest
@testable import ThematicAnalysis

final class AnalysisAssistantTests: XCTestCase {
    @MainActor
    func testAssistantDefaultsToMethodNeutralDataConversation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("assistant-default-method-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AnalysisStore(
            storageRoot: root,
            initialProject: AnalysisProject(name: "Araştırma", interviews: [], themes: [])
        )

        XCTAssertEqual(store.analysisMethodProfile, .general)
    }

    @MainActor
    func testConversationHistoryPersistsMessagesAndSelection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("conversation-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AnalysisConversationStore(storageRoot: root)
        let firstID = try XCTUnwrap(store.selectedConversationID)
        store.append(.user("Temalar arasındaki gerilimi incele"), to: firstID)
        let secondID = store.createConversation()
        store.append(.user("Aykırı örnekleri bul"), to: secondID)

        let restored = AnalysisConversationStore(storageRoot: root)

        XCTAssertEqual(restored.conversations.count, 2)
        XCTAssertEqual(restored.selectedConversationID, secondID)
        XCTAssertEqual(restored.selectedConversation?.messages.first?.text, "Aykırı örnekleri bul")
        XCTAssertEqual(
            restored.conversations.first(where: { $0.id == firstID })?.title,
            "Temalar arasındaki gerilimi incele"
        )
    }

    @MainActor
    func testConversationHistoryIsSeparatedByProjectStorageRoot() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("conversation-projects-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let first = AnalysisConversationStore(storageRoot: base.appendingPathComponent("birinci"))
        let firstID = try XCTUnwrap(first.selectedConversationID)
        first.append(.user("Birinci proje mesajı"), to: firstID)

        let second = AnalysisConversationStore(storageRoot: base.appendingPathComponent("ikinci"))

        XCTAssertEqual(second.conversations.count, 1)
        XCTAssertTrue(second.selectedMessages.isEmpty)
    }

    func testContextContainsThemeNarrativeAndCodedEvidence() throws {
        let root = ThemeNode(name: "Güven", parentID: nil, colorIndex: 0, note: "Sisteme duyulan güven")
        let child = ThemeNode(name: "Doğrulama", parentID: root.id, colorIndex: 0)
        let segment = TranscriptSegment(
            order: 1,
            part: nil,
            speaker: "K1",
            start: "00:10",
            end: "00:20",
            text: "Önemli yanıtları başka bir kaynaktan kontrol ederim."
        )
        let interview = Interview(
            name: "Görüşme 1",
            participant: "Katılımcı 1",
            segments: [segment],
            codingUnits: [
                CodingUnit(segmentIDs: [segment.id], themeIDs: [child.id], memo: "Eleştirel kullanım")
            ]
        )
        let project = AnalysisProject(name: "Araştırma", interviews: [interview], themes: [root, child])

        let context = try AnalysisAssistantContextBuilder.makeContext(from: project)

        XCTAssertTrue(context.contains("Sisteme duyulan güven"))
        XCTAssertTrue(context.contains("Güven › Doğrulama"))
        XCTAssertTrue(context.contains("Önemli yanıtları başka bir kaynaktan kontrol ederim."))
        XCTAssertTrue(context.contains("Eleştirel kullanım"))
    }

    func testContextAppliesBriefScopeAndSurroundingTranscriptRows() throws {
        let theme = ThemeNode(name: "Güven", parentID: nil, colorIndex: 0)
        let before = TranscriptSegment(order: 1, part: nil, speaker: "G", start: "00:01", end: "00:03", text: "Bunu nasıl kontrol ediyorsunuz?")
        let evidence = TranscriptSegment(order: 2, part: nil, speaker: "K", start: "00:04", end: "00:08", text: "Kaynağa yeniden bakıyorum.")
        let after = TranscriptSegment(order: 3, part: nil, speaker: "G", start: "00:09", end: "00:10", text: "Bir örnek verebilir misiniz?")
        let selectedInterview = Interview(
            name: "Görüşme 1",
            participant: "K1",
            segments: [before, evidence, after],
            codingUnits: [CodingUnit(segmentIDs: [evidence.id], themeIDs: [theme.id], memo: "")]
        )
        let excludedSegment = TranscriptSegment(order: 1, part: nil, speaker: "K", start: "", end: "", text: "Başka görüşmedeki veri")
        let excludedInterview = Interview(
            name: "Görüşme 2",
            participant: "K2",
            segments: [excludedSegment],
            codingUnits: [CodingUnit(segmentIDs: [excludedSegment.id], themeIDs: [theme.id], memo: "")]
        )
        let project = AnalysisProject(
            name: "Araştırma",
            interviews: [selectedInterview, excludedInterview],
            themes: [theme]
        )
        let brief = AnalysisBrief(
            researchQuestion: "Katılımcılar güveni nasıl kuruyor?",
            theoreticalApproach: "Yorumlayıcı",
            researcherPosition: "Teknoloji araştırmacısı",
            analysisUnit: "Konuşma dönüşü",
            exclusions: "Görüşmeci görüşlerini tema sayma"
        )
        let scope = AnalysisAssistantScope(
            kind: .interview,
            interviewID: selectedInterview.id,
            themeID: nil,
            surroundingRowCount: 1
        )

        let snapshot = try AnalysisAssistantContextBuilder.makeSnapshot(
            from: project,
            brief: brief,
            scope: scope
        )

        XCTAssertTrue(snapshot.json.contains("Katılımcılar güveni nasıl kuruyor?"))
        XCTAssertTrue(snapshot.json.contains("Bunu nasıl kontrol ediyorsunuz?"))
        XCTAssertTrue(snapshot.json.contains("Bir örnek verebilir misiniz?"))
        XCTAssertFalse(snapshot.json.contains("Başka görüşmedeki veri"))
        XCTAssertEqual(snapshot.evidence.count, 1)
    }

    @MainActor
    func testResearcherReviewDecisionPersistsWithConversation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("assistant-review-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let response = AnalysisAssistantResponse(title: "Analiz", blocks: [], followUpQuestions: [])
        let store = AnalysisConversationStore(storageRoot: root)
        let conversationID = try XCTUnwrap(store.selectedConversationID)
        let message = AnalysisChatMessage.assistant(response)
        store.append(message, to: conversationID)
        store.setReviewDecision(.revise, messageID: message.id, conversationID: conversationID)

        let restored = AnalysisConversationStore(storageRoot: root)

        XCTAssertEqual(restored.selectedMessages.first?.reviewDecision, .revise)
    }

    func testModelCatalogFiltersSpecializedModelsAndPrioritizesRecommendedModels() {
        let models = [
            OpenAIAnalysisModel(id: "gpt-6-luna", created: nil, ownedBy: nil),
            OpenAIAnalysisModel(id: "gpt-6.1-sol", created: nil, ownedBy: nil),
            OpenAIAnalysisModel(id: "gpt-image-2", created: nil, ownedBy: nil),
            OpenAIAnalysisModel(id: "gpt-realtime-2", created: nil, ownedBy: nil),
            OpenAIAnalysisModel(id: "text-embedding-3-large", created: nil, ownedBy: nil),
            OpenAIAnalysisModel(id: "gpt-6.1-sol-2026-09-30", created: nil, ownedBy: nil),
            OpenAIAnalysisModel(id: "gpt-5-chat-latest", created: nil, ownedBy: nil),
            OpenAIAnalysisModel(id: "gpt-7", created: nil, ownedBy: nil)
        ]

        XCTAssertEqual(
            AnalysisModelCatalog.compatibleModelIDs(from: models),
            ["gpt-6.1-sol", "gpt-6-luna", "gpt-7"]
        )
    }

    func testResponsesRequestUsesStructuredOutputAndDisablesStorage() throws {
        let data = try OpenAIAnalysisAssistantService.makeRequestData(
            configuration: .defaults(modelID: "gpt-6.1-sol"),
            projectContext: "{\"project\":\"Test\"}",
            messages: [.user("Temaları karşılaştır")]
        )
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        let inputText = content.first { $0["type"] as? String == "input_text" }?["text"] as? String

        XCTAssertEqual(body["model"] as? String, "gpt-6.1-sol")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
        XCTAssertTrue(inputText?.contains("Temaları karşılaştır") == true)
    }

    func testResponsesRequestIncludesAttachedFileAsBase64Input() throws {
        let attachment = AnalysisFileAttachment(
            filename: "notlar.txt",
            mimeType: "text/plain",
            data: Data("kanıt".utf8)
        )
        let data = try OpenAIAnalysisAssistantService.makeRequestData(
            configuration: .defaults(modelID: "gpt-6.1-sol"),
            projectContext: "{}",
            messages: [.user("Bu dosyayı incele", attachments: [attachment])]
        )
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        let file = try XCTUnwrap(content.first { $0["type"] as? String == "input_file" })

        XCTAssertEqual(file["filename"] as? String, "notlar.txt")
        XCTAssertEqual(file["file_data"] as? String, "data:text/plain;base64,a2FuxLF0")
    }

    func testCapabilitiesChangeWithSelectedModel() {
        let sol = OpenAIModelCapabilityCatalog.capabilities(for: "gpt-6.1-sol")
        let terra = OpenAIModelCapabilityCatalog.capabilities(for: "gpt-5.6-terra")
        let legacy = OpenAIModelCapabilityCatalog.capabilities(for: "gpt-4.1")

        XCTAssertEqual(sol.reasoningEfforts, ["low", "medium", "high", "xhigh", "max"])
        XCTAssertFalse(sol.reasoningEfforts.contains("none"))
        XCTAssertTrue(terra.reasoningEfforts.contains("none"))
        XCTAssertTrue(terra.supportsReasoningMode)
        XCTAssertFalse(legacy.supportsReasoning)
        XCTAssertEqual(legacy.maximumOutputTokens, 32_768)
    }

    func testRequestAddsReasoningSettingsAndSuppressesSamplingWhenReasoningIsEnabled() throws {
        let configuration = OpenAIAnalysisConfiguration(
            modelID: "gpt-5.6-terra",
            reasoningEffort: "high",
            reasoningMode: "pro",
            reasoningContext: "all_turns",
            reasoningSummary: "concise",
            verbosity: "high",
            maxOutputTokens: 12_000,
            temperatureEnabled: true,
            temperature: 0.4,
            topPEnabled: true,
            topP: 0.8,
            topLogprobsEnabled: true,
            topLogprobs: 5,
            serviceTier: "flex",
            truncation: "auto",
            promptCachingEnabled: true,
            promptCacheMode: "implicit",
            inputModeration: "block",
            outputModeration: "score"
        )

        let data = try OpenAIAnalysisAssistantService.makeRequestData(
            configuration: configuration,
            projectContext: "{}",
            messages: [.user("Analiz et")]
        )
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
        let text = try XCTUnwrap(body["text"] as? [String: Any])

        XCTAssertEqual(reasoning["effort"] as? String, "high")
        XCTAssertEqual(reasoning["mode"] as? String, "pro")
        XCTAssertEqual(reasoning["context"] as? String, "all_turns")
        XCTAssertEqual(reasoning["summary"] as? String, "concise")
        XCTAssertEqual(text["verbosity"] as? String, "high")
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["top_p"])
        XCTAssertNil(body["top_logprobs"])
        XCTAssertEqual(body["service_tier"] as? String, "flex")
        XCTAssertEqual(body["truncation"] as? String, "auto")
        XCTAssertNotNil(body["prompt_cache_options"])
        XCTAssertNotNil(body["moderation"])
    }

    func testSamplingSettingsAreSentWhenReasoningIsNone() throws {
        var configuration = OpenAIAnalysisConfiguration.defaults(modelID: "gpt-5.6-luna")
        configuration = .init(
            modelID: configuration.modelID,
            reasoningEffort: "none",
            reasoningMode: configuration.reasoningMode,
            reasoningContext: configuration.reasoningContext,
            reasoningSummary: configuration.reasoningSummary,
            verbosity: configuration.verbosity,
            maxOutputTokens: configuration.maxOutputTokens,
            temperatureEnabled: true,
            temperature: 0.35,
            topPEnabled: true,
            topP: 0.9,
            topLogprobsEnabled: true,
            topLogprobs: 3,
            serviceTier: configuration.serviceTier,
            truncation: configuration.truncation,
            promptCachingEnabled: configuration.promptCachingEnabled,
            promptCacheMode: configuration.promptCacheMode,
            inputModeration: configuration.inputModeration,
            outputModeration: configuration.outputModeration
        )
        let data = try OpenAIAnalysisAssistantService.makeRequestData(
            configuration: configuration,
            projectContext: "{}",
            messages: [.user("Özetle")]
        )
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(body["temperature"] as? Double, 0.35)
        XCTAssertEqual(body["top_p"] as? Double, 0.9)
        XCTAssertEqual(body["top_logprobs"] as? Int, 3)
        XCTAssertEqual(body["include"] as? [String], ["message.output_text.logprobs"])
    }

    func testDecodesStructuredResponseBlocks() throws {
        let expected = AnalysisAssistantResponse(
            title: "Tema karşılaştırması",
            blocks: [
                .init(
                    kind: .table,
                    title: "Özet",
                    text: "",
                    items: [],
                    columns: ["Tema", "Sıklık"],
                    rows: [.init(cells: ["Güven", "3"])],
                    chart: []
                )
            ],
            followUpQuestions: ["Aykırı örnekleri inceleyelim mi?"]
        )
        let payload = String(decoding: try JSONEncoder().encode(expected), as: UTF8.self)
        let envelope: [String: Any] = [
            "output": [[
                "type": "message",
                "content": [["type": "output_text", "text": payload]]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)

        XCTAssertEqual(try OpenAIAnalysisAssistantService.decodeResponse(data), expected)
    }

    func testContextCreatesStableTraceableEvidenceIDs() throws {
        let theme = ThemeNode(name: "Güven", parentID: nil, colorIndex: 0)
        let segment = TranscriptSegment(order: 1, part: nil, speaker: "K1", start: "", end: "", text: "Kontrol ederim.")
        let unitID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let unit = CodingUnit(id: unitID, segmentIDs: [segment.id], themeIDs: [theme.id], memo: "")
        let interview = Interview(name: "Görüşme", participant: "K1", segments: [segment], codingUnits: [unit])
        let project = AnalysisProject(name: "Araştırma", interviews: [interview], themes: [theme])

        let snapshot = try AnalysisAssistantContextBuilder.makeSnapshot(from: project)

        XCTAssertEqual(snapshot.evidence.first?.evidenceID, "E-123456781234")
        XCTAssertEqual(snapshot.evidence.first?.segmentIDs, [segment.id])
        XCTAssertTrue(snapshot.json.contains("\"evidence_id\" : \"E-123456781234\""))
        XCTAssertEqual(
            AnalysisAssistantContextBuilder.stableEvidenceID(for: unitID),
            AnalysisAssistantContextBuilder.stableEvidenceID(for: unitID)
        )
    }

    func testRequestIncludesSelectedMethodProfileAndEvidenceSchema() throws {
        let data = try OpenAIAnalysisAssistantService.makeRequestData(
            configuration: .defaults(modelID: "gpt-6.1-sol"),
            projectContext: "{}",
            methodProfile: .framework,
            messages: [.user("Karşılaştır")]
        )
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let instructions = try XCTUnwrap(body["instructions"] as? String)
        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        let required = try XCTUnwrap(schema["required"] as? [String])

        XCTAssertTrue(instructions.contains(AnalysisMethodProfile.framework.title))
        XCTAssertTrue(instructions.contains("vaka"))
        XCTAssertTrue(required.contains("evidence_references"))
    }

    func testRejectsResponseThatReferencesUnknownEvidence() throws {
        let response = AnalysisAssistantResponse(
            title: "Yanıt",
            blocks: [],
            followUpQuestions: [],
            evidenceReferences: [.init(evidenceID: "E-UYDURMA", claim: "Desteklenmeyen iddia")]
        )
        let payload = String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
        let envelope: [String: Any] = [
            "output": [[
                "type": "message",
                "content": [["type": "output_text", "text": payload]]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)

        XCTAssertThrowsError(
            try OpenAIAnalysisAssistantService.decodeResponse(data, validEvidenceIDs: ["E-GERCEK"])
        ) { error in
            XCTAssertEqual(error as? OpenAIAnalysisAssistantError, .invalidStructuredResponse)
        }
    }

    func testSavesMarkdownMemoAndAuditTrail() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("assistant-artifacts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let response = AnalysisAssistantResponse(
            title: "Güven analizi",
            blocks: [.init(kind: .paragraph, title: "Yorum", text: "Kanıtlı yorum.", items: [], columns: [], rows: [], chart: [])],
            followUpQuestions: [],
            evidenceReferences: [.init(evidenceID: "E-123", claim: "Doğrulama pratiği")]
        )
        let provenance = AnalysisRunProvenance(
            modelID: "gpt-test",
            methodProfileID: AnalysisMethodProfile.reflexive.rawValue,
            promptVersion: AnalysisRunProvenance.promptVersion,
            createdAt: Date(timeIntervalSince1970: 0),
            evidenceScopeIDs: ["E-123"]
        )

        let memoURL = try AnalysisAssistantArtifactStore.saveMemo(
            response: response,
            provenance: provenance,
            storageRoot: root
        )
        try AnalysisAssistantArtifactStore.appendAudit(
            event: .memoSaved,
            conversationID: UUID(),
            messageID: UUID(),
            response: response,
            provenance: provenance,
            artifactPath: memoURL.path,
            storageRoot: root
        )

        let memo = try String(contentsOf: memoURL, encoding: .utf8)
        XCTAssertTrue(memo.contains("AI destekli analiz notu"))
        XCTAssertTrue(memo.contains("`E-123`"))
        let auditURL = root.appendingPathComponent("AnalizAsistani/denetim-kaydi.json")
        let entries = try JSONDecoder.tematik.decode([AnalysisAuditEntry].self, from: Data(contentsOf: auditURL))
        XCTAssertEqual(entries.first?.event, .memoSaved)
        XCTAssertEqual(entries.first?.artifactPath, memoURL.path)
    }

    @MainActor
    func testSavedMemoStoreLoadsGeneratedMarkdownForInAppReading() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("saved-memo-library-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let response = AnalysisAssistantResponse(
            title: "Tema gerilimleri",
            blocks: [
                .init(
                    kind: .bullets,
                    title: "Bulgular",
                    text: "",
                    items: ["Güven ile kuşku birlikte ilerliyor."],
                    columns: [],
                    rows: [],
                    chart: []
                )
            ],
            followUpQuestions: ["Aykırı örnekleri inceleyelim mi?"],
            evidenceReferences: [.init(evidenceID: "E-456", claim: "Gerilim örneği")]
        )
        let provenance = AnalysisRunProvenance(
            modelID: "gpt-library-test",
            methodProfileID: AnalysisMethodProfile.codebook.rawValue,
            promptVersion: "2.0",
            createdAt: .now,
            evidenceScopeIDs: ["E-456"]
        )
        let url = try AnalysisAssistantArtifactStore.saveMemo(
            response: response,
            provenance: provenance,
            storageRoot: root
        )

        let parsed = try SavedAnalysisMemo.load(from: url)
        let store = SavedAnalysisMemoStore(storageRoot: root)

        XCTAssertEqual(parsed.title, "Tema gerilimleri")
        XCTAssertEqual(parsed.modelID, "gpt-library-test")
        XCTAssertEqual(parsed.methodProfileID, AnalysisMethodProfile.codebook.rawValue)
        XCTAssertTrue(parsed.sections.contains(where: { $0.title == "Bulgular" }))
        XCTAssertEqual(store.memos.map(\.title), ["Tema gerilimleri"])
        XCTAssertEqual(store.selectedMemo?.title, "Tema gerilimleri")
    }
}
