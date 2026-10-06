import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: AnalysisStore
    let onShowProjects: () -> Void
    @AppStorage(AppLocalization.languageKey) private var appLanguage = AppLanguage.english.rawValue
    @StateObject private var assistantWorkspace: AnalysisAssistantWorkspaceStore
    @State private var section: WorkspaceSection? = .participants
    @State private var showProjectRestore = false
    @State private var pendingRestoreURL: URL?

    init(store: AnalysisStore, onShowProjects: @escaping () -> Void) {
        self.store = store
        self.onShowProjects = onShowProjects
        _assistantWorkspace = StateObject(
            wrappedValue: AnalysisAssistantWorkspaceStore(storageRoot: store.storageRoot)
        )
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguage) ?? .english
    }

    private var navigationTitle: String {
        AppLocalization.string(section?.rawValue ?? "Tematik Analiz", language: selectedLanguage)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $section, onShowProjects: onShowProjects)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            Group {
                switch section ?? .coding {
                case .addParticipant:
                    ParticipantCreationView(
                        store: store,
                        onCancel: { section = .participants },
                        onSaved: { section = .coding }
                    )
                case .participants:
                    ParticipantDirectoryView(store: store)
                case .transcript: TranscriptTableView(store: store, codingMode: false)
                case .coding: CodingWorkspaceView(store: store)
                case .coded: CodedQuotesView(store: store)
                case .overview: ProjectOverviewView(store: store)
                case .map: ThemeMapView(store: store)
                case .assistant:
                    AnalysisAssistantView(
                        store: store,
                        workspaceStore: assistantWorkspace,
                        onOpenContext: { section = .analysisContext },
                        onOpenEvidence: { evidence in
                            store.selectedInterviewID = evidence.interviewID
                            store.selectedSegmentIDs = Set(evidence.segmentIDs)
                            section = .transcript
                        }
                    )
                case .analysisContext:
                    AnalysisAssistantContextView(
                        workspace: assistantWorkspace,
                        project: store.project,
                        themePath: store.themePathName(for:)
                    )
                case .savedAnalyses:
                    SavedAnalysisMemosView(storageRoot: store.storageRoot)
                case .profile,
                     .frequency,
                     .milesMatrix,
                     .prevalence,
                     .frameworkMatrix:
                    DebugLabView(
                        store: store,
                        module: section?.analyticsModule ?? .profile,
                        isExperimental: false
                    )
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if section != .addParticipant {
                        if section == .transcript || section == .coding || section == .coded {
                            Picker("Görüşme", selection: $store.selectedInterviewID) {
                                ForEach(store.project.interviews) { interview in
                                    Text(interview.name).tag(Optional(interview.id))
                                }
                            }
                            .frame(maxWidth: 220)
                        }
                        Menu {
                            Button("Tam Yedek Al…") {
                                do {
                                    if let url = try ExportService.exportProjectArchive(store: store) {
                                        store.lastMessage = "Tam yedek oluşturuldu: \(url.lastPathComponent)"
                                    }
                                } catch { store.lastMessage = "Yedek oluşturulamadı: \(error.localizedDescription)" }
                            }
                            Button("Yedeği Geri Yükle…") { showProjectRestore = true }
                            Divider()
                            Button("Yerel Hızlı Yedek") { store.createBackup() }
                        } label: {
                            Label("Yedek", systemImage: "externaldrive.badge.timemachine")
                        }
                        .help("Tam proje yedeği al veya daha önceki yedeği geri yükle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if store.isImporting || store.lastMessage != "Hazır" {
                    StatusBar(message: store.lastMessage, isBusy: store.isImporting)
                }
            }
        }
        .fileImporter(
            isPresented: $showProjectRestore,
            allowedContentTypes: [.zip, .json],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result else {
                if case let .failure(error) = result { store.lastMessage = error.localizedDescription }
                return
            }
            pendingRestoreURL = urls.first
        }
        .alert("Proje yedeği geri yüklensin mi?", isPresented: Binding(
            get: { pendingRestoreURL != nil },
            set: { if !$0 { pendingRestoreURL = nil } }
        )) {
            Button("Vazgeç", role: .cancel) { pendingRestoreURL = nil }
            Button("Yedeği Geri Yükle", role: .destructive) {
                guard let url = pendingRestoreURL else { return }
                pendingRestoreURL = nil
                Task { await store.restoreProject(from: url) }
            }
        } message: {
            Text("Mevcut proje önce yerel olarak yedeklenecek, ardından seçtiğiniz arşiv açılacak.")
        }
    }
}

private struct StatusBar: View {
    let message: String
    let isBusy: Bool
    var body: some View {
        HStack(spacing: 8) {
            if isBusy { ProgressView().controlSize(.small) }
            Text(verbatim: AppLocalization.string(message)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12).frame(height: 28)
        .background(.bar)
    }
}
