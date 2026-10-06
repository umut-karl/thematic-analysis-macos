import SwiftUI

struct AnalysisAssistantContextView: View {
    @ObservedObject var workspace: AnalysisAssistantWorkspaceStore
    let project: AnalysisProject
    let themePath: (UUID) -> String
    @AppStorage(AppLocalization.languageKey) private var appLanguage = AppLanguage.english.rawValue

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguage) ?? .english
    }

    private func localized(_ source: String) -> String {
        AppLocalization.string(source, language: selectedLanguage)
    }

    private var surroundingRowsTitle: String {
        let count = workspace.scope.surroundingRowCount
        if selectedLanguage == .english {
            return "\(count) transcript row(s) before and after each item of evidence"
        }
        return "Kanıt çevresinde \(count) önceki/sonraki transkript satırı"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                    contextSection(title: localized("Analiz Brifi")) {
                        ContextMultilineField(
                            title: localized("Araştırma sorusu"),
                            text: $workspace.brief.researchQuestion
                        )
                        ContextSingleLineField(
                            title: localized("Kuramsal veya epistemolojik yaklaşım"),
                            text: $workspace.brief.theoreticalApproach
                        )
                        ContextMultilineField(
                            title: localized("Araştırmacının konumlanışı ve varsayımları"),
                            text: $workspace.brief.researcherPosition
                        )
                        ContextSingleLineField(
                            title: localized("Analiz birimi"),
                            text: $workspace.brief.analysisUnit
                        )
                        ContextMultilineField(
                            title: localized("Kapsam dışında tutulacak veri veya yorumlar"),
                            text: $workspace.brief.exclusions
                        )
                    }

                    contextSection(title: localized("Veri Kapsamı")) {
                        LabeledContent(localized("Kapsam")) {
                            Picker("", selection: $workspace.scope.kind) {
                                Text(verbatim: localized("Tüm proje")).tag(AnalysisAssistantScope.Kind.project)
                                Text(verbatim: localized("Tek görüşme")).tag(AnalysisAssistantScope.Kind.interview)
                                Text(verbatim: localized("Tema dalı")).tag(AnalysisAssistantScope.Kind.theme)
                            }
                            .labelsHidden()
                            .frame(maxWidth: 240)
                        }

                        if workspace.scope.kind == .interview {
                            LabeledContent(localized("Görüşme")) {
                                Picker("", selection: $workspace.scope.interviewID) {
                                    Text(verbatim: localized("Seçin")).tag(Optional<UUID>.none)
                                    ForEach(project.interviews) { interview in
                                        Text("\(interview.participant) · \(interview.name)").tag(Optional(interview.id))
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 320)
                            }
                        }

                        if workspace.scope.kind == .theme {
                            LabeledContent(localized("Tema")) {
                                Picker("", selection: $workspace.scope.themeID) {
                                    Text(verbatim: localized("Seçin")).tag(Optional<UUID>.none)
                                    ForEach(project.themes) { theme in
                                        Text(themePath(theme.id)).tag(Optional(theme.id))
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 320)
                            }
                        }

                        Divider()
                        Stepper(
                            surroundingRowsTitle,
                            value: $workspace.scope.surroundingRowCount,
                            in: 0...10
                        )
                        Text(verbatim: localized("Konuşma bağlamı özellikle kısa cevapların, görüşmeci yönlendirmelerinin ve sıralı etkileşimin yorumlanmasını kolaylaştırır."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !workspace.persistenceError.isEmpty {
                        Label(workspace.persistenceError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
            }
            .frame(maxWidth: 760)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(minWidth: 560, minHeight: 500)
        .onAppear { workspace.normalize(for: project) }
        .onChange(of: workspace.scope.kind) {
            switch workspace.scope.kind {
            case .project:
                workspace.scope.interviewID = nil
                workspace.scope.themeID = nil
            case .interview:
                workspace.scope.themeID = nil
                if workspace.scope.interviewID == nil {
                    workspace.scope.interviewID = project.interviews.first?.id
                }
            case .theme:
                workspace.scope.interviewID = nil
                if workspace.scope.themeID == nil {
                    workspace.scope.themeID = project.themes.first?.id
                }
            }
        }
    }

    private func contextSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }
}

private struct ContextSingleLineField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
                .font(.callout.weight(.medium))
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(Text(verbatim: title))
        }
    }
}

private struct ContextMultilineField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
                .font(.callout.weight(.medium))
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 64)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }
                .accessibilityLabel(Text(verbatim: title))
        }
    }
}
