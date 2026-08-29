import Foundation

@MainActor
final class ProjectLibraryStore: ObservableObject {
    @Published private(set) var projects: [ProjectLibraryItem] = []
    @Published private(set) var activeProjectStore: AnalysisStore?
    @Published private(set) var activeProjectID: UUID?
    @Published var lastMessage = "Select a project or create a new one."
    @Published var isCreatingProject = false

    private let fileManager = FileManager.default
    private let storageRoot: URL
    private let projectsRoot: URL
    private let indexURL: URL
    private let legacyMigrationMarkerURL: URL

    init(storageRoot: URL? = nil, includeDemoProject: Bool = true) {
        let base = storageRoot ?? Self.defaultStorageRoot()
        self.storageRoot = base
        projectsRoot = base.appendingPathComponent("Projects", isDirectory: true)
        indexURL = base.appendingPathComponent("project-library.json")
        legacyMigrationMarkerURL = base.appendingPathComponent("legacy-project-migrated")

        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        loadIndex()
        migrateLegacyProjectIfNeeded()
        refreshProjectMetadata()
        if includeDemoProject { installDemoProjectIfNeeded() }
    }

    var sortedProjects: [ProjectLibraryItem] {
        projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func createProject(named name: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            lastMessage = "Project name cannot be empty."
            return false
        }

        closeProject()
        let item = ProjectLibraryItem(name: cleanName)
        let root = projectRoot(for: item)
        let project = AnalysisProject(name: cleanName, interviews: [], themes: [])
        let store = AnalysisStore(storageRoot: root, initialProject: project)
        projects.append(item)
        persistIndex()
        activeProjectID = item.id
        activeProjectStore = store
        lastMessage = "\(cleanName) created."
        return true
    }

    private func installDemoProjectIfNeeded() {
        if let index = projects.firstIndex(where: {
            $0.isDemo == true || $0.name == "Demo — AI-Assisted Work"
        }) {
            if projects[index].isDemo != true {
                projects[index].isDemo = true
                persistIndex()
            }
            return
        }

        let project = DemoProjectFactory.makeProject()
        let item = ProjectLibraryItem(
            name: project.name,
            participantCount: project.interviews.count,
            codingUnitCount: project.interviews.reduce(0) { $0 + $1.codingUnits.count },
            isDemo: true
        )
        let root = projectRoot(for: item)
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder.thematic.encode(project)
                .write(to: root.appendingPathComponent("active-project.json"), options: .atomic)
            projects.append(item)
            persistIndex()
        } catch {
            lastMessage = "Could not install the demo project: \(error.localizedDescription)"
        }
    }

    func openProject(_ item: ProjectLibraryItem) {
        closeProject()
        let root = projectRoot(for: item)
        guard fileManager.fileExists(atPath: root.appendingPathComponent("active-project.json").path) else {
            lastMessage = "Project file could not be found."
            return
        }
        activeProjectID = item.id
        activeProjectStore = AnalysisStore(storageRoot: root)
        lastMessage = "\(item.name) opened."
    }

    func closeProject() {
        guard let store = activeProjectStore else { return }
        store.persist()
        if let id = activeProjectID, let index = projects.firstIndex(where: { $0.id == id }) {
            projects[index].name = store.project.name
            projects[index].updatedAt = store.project.updatedAt
            projects[index].participantCount = store.project.interviews.count
            projects[index].codingUnitCount = store.project.interviews.reduce(0) { $0 + $1.codingUnits.count }
            persistIndex()
        }
        activeProjectStore = nil
        activeProjectID = nil
        lastMessage = "Project library"
    }

    func importProject(from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let project = try ExportService.readProject(at: url)
            closeProject()
            let item = ProjectLibraryItem(
                name: project.name,
                updatedAt: project.updatedAt,
                participantCount: project.interviews.count,
                codingUnitCount: project.interviews.reduce(0) { $0 + $1.codingUnits.count }
            )
            let store = AnalysisStore(storageRoot: projectRoot(for: item), initialProject: project)
            projects.append(item)
            persistIndex()
            activeProjectID = item.id
            activeProjectStore = store
            lastMessage = "\(project.name) was added to the library."
        } catch {
            lastMessage = "Could not open project: \(error.localizedDescription)"
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder.thematic.decode(ProjectLibraryIndex.self, from: data) else {
            projects = []
            return
        }
        projects = index.projects.filter {
            fileManager.fileExists(atPath: projectRoot(for: $0).appendingPathComponent("active-project.json").path)
        }
    }

    private func migrateLegacyProjectIfNeeded() {
        let legacyURL = storageRoot.appendingPathComponent("active-project.json")
        guard !fileManager.fileExists(atPath: legacyMigrationMarkerURL.path),
              fileManager.fileExists(atPath: legacyURL.path),
              let data = try? Data(contentsOf: legacyURL),
              let project = try? JSONDecoder.thematic.decode(AnalysisProject.self, from: data) else { return }

        let item = ProjectLibraryItem(
            name: project.name,
            updatedAt: project.updatedAt,
            participantCount: project.interviews.count,
            codingUnitCount: project.interviews.reduce(0) { $0 + $1.codingUnits.count }
        )
        let destinationRoot = projectRoot(for: item)
        do {
            try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
            try data.write(to: destinationRoot.appendingPathComponent("active-project.json"), options: .atomic)
            projects.append(item)
            persistIndex()
            try Data().write(to: legacyMigrationMarkerURL, options: .atomic)
            lastMessage = "The existing workspace was added to the project library."
        } catch {
            lastMessage = "The existing workspace could not be migrated: \(error.localizedDescription)"
        }
    }

    private func refreshProjectMetadata() {
        var changed = false
        for index in projects.indices {
            let url = projectRoot(for: projects[index]).appendingPathComponent("active-project.json")
            guard let data = try? Data(contentsOf: url),
                  let project = try? JSONDecoder.thematic.decode(AnalysisProject.self, from: data) else { continue }
            let participantCount = project.interviews.count
            let codingUnitCount = project.interviews.reduce(0) { $0 + $1.codingUnits.count }
            if projects[index].name != project.name
                || projects[index].updatedAt != project.updatedAt
                || projects[index].participantCount != participantCount
                || projects[index].codingUnitCount != codingUnitCount {
                projects[index].name = project.name
                projects[index].updatedAt = project.updatedAt
                projects[index].participantCount = participantCount
                projects[index].codingUnitCount = codingUnitCount
                changed = true
            }
        }
        if changed { persistIndex() }
    }

    private func persistIndex() {
        do {
            try JSONEncoder.thematic.encode(ProjectLibraryIndex(projects: projects))
                .write(to: indexURL, options: .atomic)
        } catch {
            lastMessage = "Could not save the project list: \(error.localizedDescription)"
        }
    }

    private func projectRoot(for item: ProjectLibraryItem) -> URL {
        projectsRoot.appendingPathComponent(item.folderName, isDirectory: true)
    }

    private static func defaultStorageRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["THEMATIC_ANALYSIS_DATA_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ThematicAnalysis", isDirectory: true)
    }
}
