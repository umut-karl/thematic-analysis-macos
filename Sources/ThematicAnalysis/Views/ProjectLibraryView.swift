import SwiftUI
import UniformTypeIdentifiers

struct AppRootView: View {
    @ObservedObject var library: ProjectLibraryStore

    var body: some View {
        Group {
            if let store = library.activeProjectStore {
                ContentView(store: store, onShowProjects: library.closeProject)
                    .id(library.activeProjectID)
            } else {
                ProjectWelcomeView(library: library)
            }
        }
        .sheet(isPresented: $library.isCreatingProject) {
            NewProjectView(library: library)
        }
    }
}

private struct ProjectWelcomeView: View {
    @ObservedObject var library: ProjectLibraryStore
    @State private var showImporter = false

    var body: some View {
        HStack(spacing: 0) {
            welcomePanel
                .frame(width: 344)
                .background(.regularMaterial)

            Divider()

            projectLibrary
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.zip, .json],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task {
                    for url in urls { await library.importProject(from: url) }
                }
            case let .failure(error):
                library.lastMessage = error.localizedDescription
            }
        }
    }

    private var welcomePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Image("BrandMark", bundle: .module)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 78, height: 78)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Thematic Analysis")
                        .font(.system(size: 29, weight: .semibold))
                    Text("Organize and code interviews, then explore relationships between themes.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
            }

            VStack(spacing: 10) {
                Button {
                    library.isCreatingProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    showImporter = true
                } label: {
                    Label("Open Project Backup…", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.top, 34)

            Spacer(minLength: 32)

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.vertical, 7)
        }
        .padding(.horizontal, 32)
        .padding(.top, 52)
        .padding(.bottom, 24)
    }

    private var projectLibrary: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Projects")
                        .font(.system(size: 27, weight: .semibold))
                    Spacer()
                    Text(library.projects.count.formatted()) + Text(" project(s)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text("Recent projects")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 24)

            if library.sortedProjects.isEmpty {
                ContentUnavailableView(
                    "No projects yet",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text("Create your first thematic analysis project.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(library.sortedProjects) { project in
                            ProjectLibraryRow(project: project) {
                                library.openProject(project)
                            }
                        }
                    }
                    .padding(1)
                }
            }

        }
        .frame(maxWidth: 900, maxHeight: .infinity)
        .padding(.horizontal, 42)
        .padding(.top, 48)
        .padding(.bottom, 22)
    }
}

private struct ProjectLibraryRow: View {
    let project: ProjectLibraryItem
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.tint.opacity(0.11))
                    Image(systemName: "doc.text")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.tint)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Group {
                        Text((project.participantCount ?? 0).formatted()) + Text(" participant(s) · ")
                        + Text((project.codingUnitCount ?? 0).formatted()) + Text(" coding item(s)")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 24)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Last edited")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(project.updatedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.075) : Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isHovered ? Color.accentColor.opacity(0.28) : Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }
}

private struct NewProjectView: View {
    @ObservedObject var library: ProjectLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Thematic Analysis Project")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Participants, transcripts, themes, and coding are stored together in this project.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Project name")
                    .font(.callout)
                    .fontWeight(.medium)
                TextField("e.g. AI Interviews", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Project") {
                    if library.createProject(named: name) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
