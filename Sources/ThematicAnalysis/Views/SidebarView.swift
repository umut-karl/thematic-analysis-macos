import SwiftUI

struct SidebarView: View {
    @Binding var selection: WorkspaceSection?
    let onShowProjects: () -> Void

    var body: some View {
        List(selection: $selection) {
            Section("Interviews and Coding") {
                Label {
                    Text(WorkspaceSection.addParticipant.localizedTitle)
                } icon: {
                    Image(systemName: WorkspaceSection.addParticipant.symbol)
                }
                    .tag(WorkspaceSection.addParticipant)

                ForEach([WorkspaceSection.participants, .transcript, .coding, .coded]) { section in
                    Label { Text(section.localizedTitle) } icon: { Image(systemName: section.symbol) }.tag(section)
                }
            }
            Section("Project Analysis") {
                ForEach([WorkspaceSection.overview, .map]) { section in
                    Label { Text(section.localizedTitle) } icon: { Image(systemName: section.symbol) }.tag(section)
                }
            }
            Section("Analytical Views") {
                ForEach(WorkspaceSection.indicatorSections) { section in
                    Label { Text(section.localizedTitle) } icon: { Image(systemName: section.symbol) }
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button(action: onShowProjects) {
                    Label("Projects", systemImage: "rectangle.stack")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .help("Open another project")

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Open API key and app settings")
            }
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.bar)
        }
    }

}
