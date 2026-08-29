import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: AnalysisStore
    let onShowProjects: () -> Void
    @State private var section: WorkspaceSection? = .participants
    @State private var showProjectRestore = false
    @State private var pendingRestoreURL: URL?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $section, onShowProjects: onShowProjects)
                .navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 280)
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
                case .profile,
                     .frequency,
                     .milesMatrix,
                     .prevalence,
                     .frameworkMatrix:
                    DebugLabView(
                        store: store,
                        module: section?.analyticsModule ?? .profile
                    )
                }
            }
            .navigationTitle(AppLocalization.string(section?.rawValue ?? "Thematic Analysis"))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if section != .addParticipant {
                        Picker("Interview", selection: $store.selectedInterviewID) {
                            ForEach(store.project.interviews) { interview in
                                Text(interview.name).tag(Optional(interview.id))
                            }
                        }
                        .frame(maxWidth: 220)
                        Menu {
                            Button("Create Full Backup…") {
                                do {
                                    if let url = try ExportService.exportProjectArchive(store: store) {
                                        store.lastMessage = "Full backup created: \(url.lastPathComponent)"
                                    }
                                } catch { store.lastMessage = "Could not create backup: \(error.localizedDescription)" }
                            }
                            Button("Restore Backup…") { showProjectRestore = true }
                            Divider()
                            Button("Quick Local Backup") { store.createBackup() }
                        } label: {
                            Label("Backup", systemImage: "externaldrive.badge.timemachine")
                        }
                        .help("Create a full project backup or restore an earlier backup")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                StatusBar(message: store.lastMessage, isBusy: store.isImporting)
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
        .alert("Restore project backup?", isPresented: Binding(
            get: { pendingRestoreURL != nil },
            set: { if !$0 { pendingRestoreURL = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingRestoreURL = nil }
            Button("Restore Backup", role: .destructive) {
                guard let url = pendingRestoreURL else { return }
                pendingRestoreURL = nil
                Task { await store.restoreProject(from: url) }
            }
        } message: {
            Text("The current project will be backed up locally before the selected archive is opened.")
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
