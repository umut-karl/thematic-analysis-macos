import SwiftUI
import UniformTypeIdentifiers

struct ParticipantDirectoryView: View {
    @ObservedObject var store: AnalysisStore
    @State private var editingInterview: Interview?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Participants").font(.title2).fontWeight(.semibold)
                    Text("Each participant is stored with their transcript and demographic information.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(16)

            Table(store.project.interviews, selection: $store.selectedInterviewID) {
                TableColumn("Participant") { interview in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(interview.participant).fontWeight(.medium)
                        Text(interview.name).font(.caption).foregroundStyle(.secondary)
                    }
                }.width(min: 150, ideal: 210)
                TableColumn("Gender") { interview in
                    Text(verbatim: AppLocalization.string(interview.participantDetails?.gender.nilIfEmpty ?? "—"))
                }
                    .width(min: 80, ideal: 100)
                TableColumn("Age") { interview in Text(interview.participantDetails?.age.nilIfEmpty ?? "—") }
                    .width(55)
                TableColumn("Education") { interview in Text(interview.participantDetails?.education.nilIfEmpty ?? "—") }
                    .width(min: 120, ideal: 170)
                TableColumn("Occupation") { interview in Text(interview.participantDetails?.occupation.nilIfEmpty ?? "—") }
                    .width(min: 120, ideal: 170)
                TableColumn("Transcript") { interview in
                    Text(interview.segments.count.formatted()) + Text(" row(s)")
                }
                    .width(90)
                TableColumn("Coding") { interview in Text(interview.codingUnits.count.formatted()) }
                    .width(70)
                TableColumn("") { interview in
                    Button {
                        editingInterview = interview
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("\(interview.participant) · \(AppLocalization.string("Edit details"))")
                    .accessibilityLabel("\(AppLocalization.string("Edit participant")): \(interview.participant)")
                }
                .width(38)
            }
            .overlay {
                if store.project.interviews.isEmpty {
                    ContentUnavailableView(
                        "No participants yet",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Add the first participant and transcript.")
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
                    Text("Add Participant").font(.title2).fontWeight(.semibold)
                    Text("Enter participant details, then continue with a transcript or audio recording.")
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

                    FormSection(title: "Interview Source", description: "Upload a transcript or convert audio to text with speaker and time information.") {
                        Picker("Source Type", selection: $source) {
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
                Button("Cancel") { onCancel() }.keyboardShortcut(.cancelAction)
                Spacer()
                if store.isImporting || isTranscribing { ProgressView().controlSize(.small) }
                Button("Save and Start Coding") {
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
        .alert("The operation could not be completed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(verbatim: AppLocalization.string(errorMessage ?? "Unknown error"))
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
                Text(transcriptURL?.lastPathComponent ?? "No file selected")
                    .fontWeight(.medium).lineLimit(1)
                Text("XLSX, CSV, or TSV")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(transcriptURL == nil ? "Choose Transcript…" : "Change File…") {
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
                    Text(audioURL?.lastPathComponent ?? "No audio file selected")
                        .fontWeight(.medium).lineLimit(1)
                    Text(audioMetadata).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(audioURL == nil ? "Choose Audio…" : "Change File…") {
                    showAudioImporter = true
                }
            }

            Divider()

            HStack(spacing: 10) {
                Label(
                    hasOpenAIAPIKey ? "OpenAI API key is ready" : "OpenAI API key required",
                    systemImage: hasOpenAIAPIKey ? "checkmark.shield.fill" : "key.slash"
                )
                .font(.callout)
                .foregroundStyle(hasOpenAIAPIKey ? Color.green : Color.secondary)
                Spacer()
                if !hasOpenAIAPIKey {
                    SettingsLink {
                        Label("Open Settings", systemImage: "gearshape")
                    }
                }
            }

            if isTranscribing {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Detecting speakers and time ranges…")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else if transcriptionResult == nil {
                Button {
                    transcribeAudio()
                } label: {
                    Label("Transcribe Audio", systemImage: "waveform.and.mic")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(audioURL == nil || !hasOpenAIAPIKey)
            }

            if let result = transcriptionResult {
                speakerMapping(result)
                transcriptPreview(result)
                Button("Transcribe Again") { transcribeAudio() }
                    .disabled(isTranscribing)
            }

            Label("The selected audio file is sent to the OpenAI API. The API key is stored in this Mac's app settings.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func speakerMapping(_ result: OpenAITranscriptionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assign Speakers").font(.callout).fontWeight(.semibold)
            Text("Name changes apply to all related transcript rows.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(result.speakers.enumerated()), id: \.element) { index, speaker in
                HStack(spacing: 10) {
                    Circle().fill(SpeakerPalette.color(index)).frame(width: 8, height: 8)
                    Text(speaker).font(.caption).monospaced().frame(width: 80, alignment: .leading)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("Speaker name", text: Binding(
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
                Text("Speaker").frame(width: 115, alignment: .leading)
                Text("Time").frame(width: 100, alignment: .leading)
                Text("Text").frame(maxWidth: .infinity, alignment: .leading)
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
        return bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Could not read file size"
    }

    private func transcribeAudio() {
        guard let audioURL else { return }
        let apiKey = OpenAIAPIKeyStore.load()
        guard !apiKey.isEmpty else {
            hasOpenAIAPIKey = false
            errorMessage = "Save your OpenAI API key in Settings first."
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
                store.lastMessage = "Audio transcription failed: \(error.localizedDescription)"
            }
            isTranscribing = false
        }
    }

    private func suggestedSpeakerNames(for speakers: [String]) -> [String: String] {
        let participant = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Dictionary(uniqueKeysWithValues: speakers.enumerated().map { index, speaker in
            let suggestion = index == 0 ? "Interviewer" : index == 1 ? participant : "Speaker \(index + 1)"
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
                    Text("Edit Participant")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Update identity and demographic details. Transcript and coding are preserved.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ParticipantInformationFields(name: $participantName, details: $details)
                    FormSection(
                        title: "Interview",
                        description: "This name appears in source lists and interview selectors."
                    ) {
                        FormField(title: "Interview name", required: true) {
                            TextField("e.g. Participant B Transcript", text: $interviewName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Changes") {
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
            FormSection(title: "Participant Details", description: "Only the participant name is required.") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow {
                        FormField(title: "Participant name", required: true, hint: "You can use a code or pseudonym instead of a real name.") {
                            TextField("e.g. Participant B or P-02", text: $name).textFieldStyle(.roundedBorder)
                        }
                        FormField(title: "Age", hint: "Optional") {
                            TextField("e.g. 34", text: $details.age).textFieldStyle(.roundedBorder).frame(maxWidth: 140)
                        }
                    }
                    GridRow {
                        FormField(title: "Gender", hint: "Optional") {
                            Picker("", selection: $details.gender) {
                                Text("Not selected").tag("")
                                Text("Woman").tag("Woman")
                                Text("Man").tag("Man")
                                Text("Non-binary").tag("Non-binary")
                                Text("Prefer not to say").tag("Prefer not to say")
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1)
                    }
                }
            }

            FormSection(title: "Demographic Information", description: "Complete the fields relevant to your research; all are optional.") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
                    GridRow {
                        FormField(title: "Education") {
                            TextField("e.g. Bachelor's degree", text: $details.education).textFieldStyle(.roundedBorder)
                        }
                        FormField(title: "Occupation") {
                            TextField("e.g. Teacher", text: $details.occupation).textFieldStyle(.roundedBorder)
                        }
                    }
                    GridRow {
                        FormField(title: "City / Region") {
                            TextField("e.g. London", text: $details.location).textFieldStyle(.roundedBorder)
                        }
                        FormField(title: "Employment Status") {
                            Picker("", selection: $details.employmentStatus) {
                                Text("Not selected").tag("")
                                Text("Employed full-time").tag("Employed full-time")
                                Text("Employed part-time").tag("Employed part-time")
                                Text("Self-employed").tag("Self-employed")
                                Text("Student").tag("Student")
                                Text("Not employed").tag("Not employed")
                                Text("Retired").tag("Retired")
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    GridRow {
                        FormField(title: "Sector / Organization") {
                            TextField("e.g. Education / Public sector", text: $details.sector).textFieldStyle(.roundedBorder)
                        }
                        FormField(title: "Professional Experience") {
                            TextField("e.g. 8 years", text: $details.experienceYears).textFieldStyle(.roundedBorder)
                        }
                    }
                    GridRow {
                        FormField(title: "Marital Status") {
                            Picker("", selection: $details.maritalStatus) {
                                Text("Not selected").tag("")
                                Text("Single").tag("Single")
                                Text("Married").tag("Married")
                                Text("Divorced").tag("Divorced")
                                Text("Widowed").tag("Widowed")
                                Text("Prefer not to say").tag("Prefer not to say")
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1)
                    }
                }
                FormField(title: "Researcher Note", hint: "Contextual or methodological notes about the participant") {
                    TextField("Optional note", text: $details.notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...4)
                }
            }
        }
    }
}

private enum ParticipantTranscriptSource: String, CaseIterable, Identifiable {
    case transcriptFile = "Transcript File"
    case audioFile = "Audio Recording"

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
                if required { Text("*").foregroundStyle(.red).accessibilityLabel(Text("required")) }
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
