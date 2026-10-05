import SwiftUI

struct SidebarView: View {
    @Binding var selection: WorkspaceSection?
    let onShowProjects: () -> Void

    var body: some View {
        List(selection: $selection) {
            Section("Görüşme ve Kodlama") {
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
            Section("Proje Analizi") {
                ForEach([WorkspaceSection.overview, .map]) { section in
                    Label { Text(section.localizedTitle) } icon: { Image(systemName: section.symbol) }.tag(section)
                }
            }
            Section("Analiz Asistanı") {
                ForEach([WorkspaceSection.assistant, .analysisContext, .savedAnalyses]) { section in
                    Label { Text(section.localizedTitle) } icon: { Image(systemName: section.symbol) }.tag(section)
                }
            }
            Section("Analitik Görünümler") {
                ForEach(WorkspaceSection.indicatorSections) { section in
                    Label { Text(section.localizedTitle) } icon: { Image(systemName: section.symbol) }
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 2) {
                Button(action: onShowProjects) {
                    SidebarFooterLabel(title: "Proje Kütüphanesi", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.plain)
                .help("Başka bir projeyi aç")

                SettingsLink {
                    SidebarFooterLabel(title: "Ayarlar", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .help("API anahtarı ve uygulama ayarlarını aç")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .overlay(alignment: .top) { Divider() }
            .background(.thinMaterial)
        }
    }

}

private struct SidebarFooterLabel: View {
    let title: String
    let systemImage: String
    @State private var isHovered = false

    var body: some View {
        Label {
            Text(verbatim: AppLocalization.string(title))
        } icon: {
            Image(systemName: systemImage)
        }
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.secondary.opacity(0.12) : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}
