import SwiftUI
import UniformTypeIdentifiers

struct ParticipantDirectoryView: View {
    @ObservedObject var store: AnalysisStore
    @State private var editingInterview: Interview?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Katılımcılar").font(.title2).fontWeight(.semibold)
                    Text("Her katılımcı kendi transkripti ve demografik bilgileriyle saklanır.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(16)

            Table(store.project.interviews, selection: $store.selectedInterviewID) {
                TableColumn("Katılımcı") { interview in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(interview.participant).fontWeight(.medium)
                        Text(interview.name).font(.caption).foregroundStyle(.secondary)
                    }
                }.width(min: 150, ideal: 210)
                TableColumn("Cinsiyet") { interview in
                    Text(verbatim: AppLocalization.string(interview.participantDetails?.gender.nilIfEmpty ?? "—"))
                }
                    .width(min: 80, ideal: 100)
                TableColumn("Yaş") { interview in Text(interview.participantDetails?.age.nilIfEmpty ?? "—") }
                    .width(55)
                TableColumn("Eğitim") { interview in Text(interview.participantDetails?.education.nilIfEmpty ?? "—") }
                    .width(min: 120, ideal: 170)
                TableColumn("Meslek") { interview in Text(interview.participantDetails?.occupation.nilIfEmpty ?? "—") }
                    .width(min: 120, ideal: 170)
                TableColumn("Transkript") { interview in
                    Text(interview.segments.count.formatted()) + Text(" satır")
                }
                    .width(90)
                TableColumn("Kodlama") { interview in Text(interview.codingUnits.count.formatted()) }
                    .width(70)
                TableColumn("") { interview in
                    Button {
                        editingInterview = interview
                    } label: {
                        Label("Düzenle", systemImage: "pencil")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("\(interview.participant) · \(AppLocalization.string("Bilgileri düzenle"))")
                    .accessibilityLabel("\(AppLocalization.string("Katılımcıyı düzenle")): \(interview.participant)")
                }
                .width(38)
            }
            .overlay {
                if store.project.interviews.isEmpty {
                    ContentUnavailableView(
                        "Henüz katılımcı yok",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("İlk katılımcıyı ve transkriptini ekleyin.")
                    )
                }
            }
        }
        .sheet(item: $editingInterview) { interview in
            ParticipantEditView(store: store, interviewID: interview.id)
        }
    }
}

struct ParticipantCreationView: View {
    @ObservedObject var store: AnalysisStore
    let onCancel: () -> Void
    let onSaved: () -> Void
    @AppStorage("hasOpenAIAPIKey") private var hasOpenAIAPIKey = false
    @State private var name = ""
    @State private var details = ParticipantDetails()
    @State private var source: ParticipantTranscriptSource = .transcriptFile
    @State private var transcriptURL: URL?
    @State private var audioURL: URL?
    @State private var showTranscriptImporter = false
    @State private var showAudioImporter = false
    @State private var isTranscribing = false
    @State private var transcriptionResult: OpenAITranscriptionResult?
    @State private var speakerNames: [String: String] = [:]
    @State private var errorMessage: String?

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !store.isImporting, !isTranscribing else { return false }
        switch source {
        case .transcriptFile:
            return transcriptURL != nil
        case .audioFile:
            guard let result = transcriptionResult else { return false }
            return result.speakers.allSatisfy {
                !(speakerNames[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Katılımcı Ekle").font(.title2).fontWeight(.semibold)
                    Text("Kişi bilgilerini girin; hazır transkript veya ses kaydıyla devam edin.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ParticipantInformationFields(name: $name, details: $details)

                    FormSection(title: "Görüşme kaynağı", description: "Hazır bir transkript yükleyin veya ses kaydını konuşmacı ve zaman bilgileriyle metne dönüştürün.") {
                        Picker("Kaynak türü", selection: $source) {
                            ForEach(ParticipantTranscriptSource.allCases) { option in
                                Label { Text(LocalizedStringKey(option.rawValue)) } icon: { Image(systemName: option.symbol) }.tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 280, alignment: .leading)

                        Group {
                            switch source {
                            case .transcriptFile:
                                transcriptFileCard
                            case .audioFile:
                                audioTranscriptionCard
                            }
                        }
                    }
                }
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            Divider()
            HStack {
                Button("Vazgeç") { onCancel() }.keyboardShortcut(.cancelAction)
                Spacer()
                if store.isImporting || isTranscribing { ProgressView().controlSize(.small) }
                Button("Kaydet ve Kodlamaya Geç") {
                    saveParticipant()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(
            isPresented: $showTranscriptImporter,
            allowedContentTypes: [UTType(filenameExtension: "xlsx")!, .commaSeparatedText, .tabSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result { transcriptURL = urls.first }
            if case let .failure(error) = result { store.lastMessage = error.localizedDescription }
        }
        .fileImporter(
            isPresented: $showAudioImporter,
            allowedContentTypes: supportedAudioTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                audioURL = urls.first
                transcriptionResult = nil
                speakerNames = [:]
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("İşlem tamamlanamadı", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Tamam", role: .cancel) { errorMessage = nil }
        } message: {
            Text(verbatim: AppLocalization.string(errorMessage ?? "Bilinmeyen hata"))
        }
        .task {
            hasOpenAIAPIKey = !OpenAIAPIKeyStore.load().isEmpty
        }
    }

    private var transcriptFileCard: some View {
        HStack(spacing: 12) {
            Image(systemName: transcriptURL == nil ? "doc.badge.plus" : "checkmark.circle.fill")
                .font(.title2).foregroundStyle(transcriptURL == nil ? Color.secondary : Color.green)
            VStack(alignment: .leading, spacing: 3) {
                Text(transcriptURL?.lastPathComponent ?? "Henüz dosya seçilmedi")
                    .fontWeight(.medium).lineLimit(1)
                Text("XLSX, CSV veya TSV")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(transcriptURL == nil ? "Transkript Seç…" : "Dosyayı Değiştir…") {
                showTranscriptImporter = true
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var audioTranscriptionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: audioURL == nil ? "waveform.badge.plus" : "checkmark.circle.fill")
                    .font(.title2).foregroundStyle(audioURL == nil ? Color.secondary : Color.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(audioURL?.lastPathComponent ?? "Henüz ses dosyası seçilmedi")
                        .fontWeight(.medium).lineLimit(1)
                    Text(audioMetadata).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(audioURL == nil ? "Ses Kaydı Seç…" : "Dosyayı Değiştir…") {
                    showAudioImporter = true
                }
            }

            Divider()

            HStack(spacing: 10) {
                Label(
                    hasOpenAIAPIKey ? "OpenAI API anahtarı hazır" : "OpenAI API anahtarı gerekli",
                    systemImage: hasOpenAIAPIKey ? "checkmark.shield.fill" : "key.slash"
                )
                .font(.callout)
                .foregroundStyle(hasOpenAIAPIKey ? Color.green : Color.secondary)
                Spacer()
                if !hasOpenAIAPIKey {
                    SettingsLink {
                        Label("Ayarları Aç", systemImage: "gearshape")
                    }
                }
            }

            if isTranscribing {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Konuşmacılar ve zaman aralıkları çıkarılıyor…")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else if transcriptionResult == nil {
                Button {
                    transcribeAudio()
                } label: {
                    Label("Sesi Metne Dönüştür", systemImage: "waveform.and.mic")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(audioURL == nil || !hasOpenAIAPIKey)
            }

            if let result = transcriptionResult {
                speakerMapping(result)
                transcriptPreview(result)
                Button("Transkripsiyonu Yeniden Oluştur") { transcribeAudio() }
                    .disabled(isTranscribing)
            }

            Label("Seçtiğiniz ses dosyası OpenAI API’ye gönderilir. API anahtarı bu Mac’teki uygulama ayarlarında tutulur.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func speakerMapping(_ result: OpenAITranscriptionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Konuşmacıları eşleştir").font(.callout).fontWeight(.semibold)
            Text("Ad değişikliği ilgili bütün transkript satırlarına uygulanır.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(result.speakers.enumerated()), id: \.element) { index, speaker in
                HStack(spacing: 10) {
                    Circle().fill(SpeakerPalette.color(index)).frame(width: 8, height: 8)
                    Text(speaker).font(.caption).monospaced().frame(width: 80, alignment: .leading)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("Konuşmacı adı", text: Binding(
                        get: { speakerNames[speaker] ?? "" },
                        set: { speakerNames[speaker] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func transcriptPreview(_ result: OpenAITranscriptionResult) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Konuşmacı").frame(width: 115, alignment: .leading)
                Text("Zaman").frame(width: 100, alignment: .leading)
                Text("Metin").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 7).background(.bar)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(result.segments) { segment in
                        HStack(alignment: .top, spacing: 10) {
                            Text(resolvedSpeaker(segment.speaker))
                                .font(.caption).fontWeight(.medium)
                                .frame(width: 115, alignment: .leading)
                            Text("\(displayTime(segment.start))–\(displayTime(segment.end))")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 100, alignment: .leading)
                            Text(segment.text).font(.callout).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        Divider()
                    }
                }
            }
            .frame(height: 220)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
    }

    private var supportedAudioTypes: [UTType] {
        OpenAITranscriptionService.supportedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
    }

    private var audioMetadata: String {
        guard let audioURL else { return "MP3, MP4, MPEG, MPGA, M4A, WAV veya WEBM · en fazla 25 MB" }
        let didAccess = audioURL.startAccessingSecurityScopedResource()
        defer { if didAccess { audioURL.stopAccessingSecurityScopedResource() } }
        let bytes = (try? audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map(Int64.init)
        return bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Dosya boyutu okunamadı"
    }

    private func transcribeAudio() {
        guard let audioURL else { return }
        let apiKey = OpenAIAPIKeyStore.load()
        guard !apiKey.isEmpty else {
            hasOpenAIAPIKey = false
            errorMessage = "OpenAI API anahtarını önce Ayarlar’dan kaydedin."
            return
        }
        isTranscribing = true
        transcriptionResult = nil
        speakerNames = [:]
        errorMessage = nil

        Task {
            do {
                let result = try await OpenAITranscriptionService.transcribe(audioURL: audioURL, apiKey: apiKey)
                transcriptionResult = result
                speakerNames = suggestedSpeakerNames(for: result.speakers)
            } catch {
                errorMessage = error.localizedDescription
                store.lastMessage = "Ses transkripsiyonu başarısız: \(error.localizedDescription)"
            }
            isTranscribing = false
        }
    }

    private func suggestedSpeakerNames(for speakers: [String]) -> [String: String] {
        let participant = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Dictionary(uniqueKeysWithValues: speakers.enumerated().map { index, speaker in
            let suggestion = index == 0 ? "Görüşmeci" : index == 1 ? participant : "Konuşmacı \(index + 1)"
            return (speaker, suggestion)
        })
    }

    private func resolvedSpeaker(_ speaker: String) -> String {
        let mapped = speakerNames[speaker]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return mapped.isEmpty ? speaker : mapped
    }

    private func displayTime(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        let hours = value / 3_600
        let minutes = (value % 3_600) / 60
        let remainder = value % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }

    private func saveParticipant() {
        switch source {
        case .transcriptFile:
            guard let transcriptURL else { return }
            Task {
                if await store.createParticipant(name: name, details: details, transcriptURL: transcriptURL) {
                    onSaved()
                }
            }
        case .audioFile:
            guard let result = transcriptionResult, let audioURL else { return }
            let interviewID = store.createDiarizedCase(
                participantName: name,
                interviewName: "",
                participantDetails: details,
                diarizedSegments: result.segments,
                speakerNames: speakerNames,
                sourceFileName: audioURL.lastPathComponent,
                model: result.model
            )
            if interviewID != nil { onSaved() }
        }
    }
}

private struct ParticipantEditView: View {
    @ObservedObject var store: AnalysisStore
    let interviewID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var participantName: String
    @State private var interviewName: String
    @State private var details: ParticipantDetails

    init(store: AnalysisStore, interviewID: UUID) {
        self.store = store
        self.interviewID = interviewID
        let interview = store.project.interviews.first(where: { $0.id == interviewID })
        _participantName = State(initialValue: interview?.participant ?? "")
        _interviewName = State(initialValue: interview?.name ?? "")
        _details = State(initialValue: interview?.participantDetails ?? ParticipantDetails())
    }

    private var canSave: Bool {
        !participantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Katılımcıyı Düzenle")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Kimlik ve demografik bilgileri güncelleyin. Transkript ve kodlamalar korunur.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Kapat")
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ParticipantInformationFields(name: $participantName, details: $details)
                    FormSection(
                        title: "Görüşme",
                        description: "Bu ad kaynak listesinde ve görüşme seçimlerinde görünür."
                    ) {
                        FormField(title: "Görüşme adı", required: true) {
                            TextField("Örn. Fatma Transkripti", text: $interviewName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                Button("Vazgeç") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Değişiklikleri Kaydet") {
                    if store.updateParticipant(
                        interviewID: interviewID,
                        participantName: participantName,
                        interviewName: interviewName,
                        details: details
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 700, idealWidth: 820, minHeight: 560, idealHeight: 680)
    }
}

private struct ParticipantInformationFields: View {
    @Binding var name: String
    @Binding var details: ParticipantDetails

    var body: some View {
        Group {
            FormSection(title: "Katılımcı bilgileri", description: "Yalnızca katılımcı adı zorunludur.") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow {
                        FormField(title: "Katılımcı adı", required: true, hint: "Gerçek ad yerine kod veya takma ad kullanabilirsiniz.") {
                            TextField("Örn. Fatma veya K-02", text: $name).textFieldStyle(.roundedBorder)
                        }
                        FormField(title: "Yaş", hint: "İsteğe bağlı") {
                            TextField("Örn. 34", text: $details.age).textFieldStyle(.roundedBorder).frame(maxWidth: 140)
                        }
                    }
                    GridRow {
                        FormField(title: "Cinsiyet", hint: "İsteğe bağlı") {
                            Picker("", selection: $details.gender) {
                                Text("Seçilmedi").tag("")
                                Text("Kadın").tag("Kadın")
                                Text("Erkek").tag("Erkek")
                                Text("Non-binary").tag("Non-binary")
                                Text("Belirtmek istemiyor").tag("Belirtmek istemiyor")
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1)
                    }
                }
            }

            FormSection(title: "Demografik bilgiler", description: "Araştırmanız için gerekli alanları doldurun; tümü isteğe bağlıdır.") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow {
                        FormField(title: "Eğitim durumu") {
                            TextField("Örn. Lisans", text: $details.education).textFieldStyle(.roundedBorder)
                        }
                        FormField(title: "Meslek") {
                            TextField("Örn. Öğretmen", text: $details.occupation).textFieldStyle(.roundedBorder)
                        }
                    }
                    GridRow {
                        FormField(title: "Şehir / bölge") {
                            TextField("Örn. İstanbul", text: $details.location).textFieldStyle(.roundedBorder)
                        }
                        FormField(title: "Çalışma durumu") {
                            Picker("", selection: $details.employmentStatus) {
                                Text("Seçilmedi").tag("")
                                Text("Tam zamanlı çalışıyor").tag("Tam zamanlı çalışıyor")
                                Text("Yarı zamanlı çalışıyor").tag("Yarı zamanlı çalışıyor")
                                Text("Serbest çalışıyor").tag("Serbest çalışıyor")
                                Text("Öğrenci").tag("Öğrenci")
                                Text("Çalışmıyor").tag("Çalışmıyor")
                                Text("Emekli").tag("Emekli")
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    GridRow {
                        FormField(title: "Sektör / kurum") {
                            TextField("Örn. Eğitim / devlet", text: $details.sector).textFieldStyle(.roundedBorder)
                        }
                        FormField(title: "Mesleki deneyim") {
                            TextField("Örn. 8 yıl", text: $details.experienceYears).textFieldStyle(.roundedBorder)
                        }
                    }
                    GridRow {
                        FormField(title: "Medeni durum") {
                            Picker("", selection: $details.maritalStatus) {
                                Text("Seçilmedi").tag("")
                                Text("Bekâr").tag("Bekâr")
                                Text("Evli").tag("Evli")
                                Text("Boşanmış").tag("Boşanmış")
                                Text("Dul").tag("Dul")
                                Text("Belirtmek istemiyor").tag("Belirtmek istemiyor")
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1)
                    }
                }
                FormField(title: "Araştırmacı notu", hint: "Katılımcıya ilişkin bağlamsal veya yöntemsel notlar") {
                    TextField("İsteğe bağlı not", text: $details.notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...4)
                }
            }
        }
    }
}

private enum ParticipantTranscriptSource: String, CaseIterable, Identifiable {
    case transcriptFile = "Transkript Dosyası"
    case audioFile = "Ses Kaydı"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .transcriptFile: "tablecells"
        case .audioFile: "waveform"
        }
    }
}

private struct FormSection<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: Content

    init(title: String, description: String = "", @ViewBuilder content: () -> Content) {
        self.title = title; self.description = description; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(.headline)
                if !description.isEmpty {
                    Text(LocalizedStringKey(description)).font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 14) { content }
            Divider()
        }
    }
}

private struct FormField<Content: View>: View {
    let title: String
    var required = false
    var hint = ""
    @ViewBuilder let content: Content

    init(title: String, required: Bool = false, hint: String = "", @ViewBuilder content: () -> Content) {
        self.title = title; self.required = required; self.hint = hint; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                Text(LocalizedStringKey(title)).font(.callout).fontWeight(.medium)
                if required { Text("*").foregroundStyle(.red).accessibilityLabel(Text("zorunlu")) }
            }
            content
            if !hint.isEmpty {
                Text(LocalizedStringKey(hint)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
