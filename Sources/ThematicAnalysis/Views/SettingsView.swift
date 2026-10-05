import SwiftUI

struct SettingsView: View {
    @AppStorage("hasOpenAIAPIKey") private var hasOpenAIAPIKey = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.turkish.rawValue
    @AppStorage("openAIAnalysisModel") private var analysisModel = AnalysisModelCatalog.defaultModelID
    @AppStorage("openAIReasoningEffort") private var reasoningEffort = "auto"
    @AppStorage("openAIReasoningMode") private var reasoningMode = "standard"
    @AppStorage("openAIReasoningContext") private var reasoningContext = "auto"
    @AppStorage("openAIReasoningSummary") private var reasoningSummary = "none"
    @AppStorage("openAIResponseVerbosity") private var responseVerbosity = "medium"
    @AppStorage("openAIMaxOutputTokens") private var maxOutputTokens = 6_000
    @AppStorage("openAITemperatureEnabled") private var temperatureEnabled = false
    @AppStorage("openAITemperature") private var temperature = 1.0
    @AppStorage("openAITopPEnabled") private var topPEnabled = false
    @AppStorage("openAITopP") private var topP = 1.0
    @AppStorage("openAITopLogprobsEnabled") private var topLogprobsEnabled = false
    @AppStorage("openAITopLogprobs") private var topLogprobs = 0
    @AppStorage("openAIServiceTier") private var serviceTier = "auto"
    @AppStorage("openAITruncation") private var truncation = "disabled"
    @AppStorage("openAIPromptCachingEnabled") private var promptCachingEnabled = true
    @AppStorage("openAIPromptCacheMode") private var promptCacheMode = "implicit"
    @AppStorage("openAIInputModeration") private var inputModeration = "off"
    @AppStorage("openAIOutputModeration") private var outputModeration = "off"
    @State private var apiKey = ""
    @State private var savedAPIKey = ""
    @State private var message = ""
    @State private var availableModels = AnalysisModelCatalog.fallbackModelIDs
    @State private var isRefreshingModels = false
    @State private var modelMessage = ""

    private var hasStoredKey: Bool {
        !savedAPIKey.isEmpty
    }

    private var canSave: Bool {
        let clean = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !clean.isEmpty && clean != savedAPIKey
    }

    private var capabilities: OpenAIModelCapabilities {
        OpenAIModelCapabilityCatalog.capabilities(for: analysisModel)
    }

    private var samplingAvailable: Bool {
        capabilities.supportsSampling(for: reasoningEffort)
    }

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label(text("Genel"), systemImage: "gearshape") }

            assistantSettings
                .tabItem { Label(text("Yapay Zekâ"), systemImage: "sparkles") }
        }
        .frame(width: 680, height: 640)
        .task {
            reload()
            loadCachedModels()
            reconcileSettings()
            await refreshModels(force: false)
        }
        .onChange(of: analysisModel) { _, _ in
            reconcileSettings()
        }
    }

    private var generalSettings: some View {
        Form {
            Section {
                Picker(text("Uygulama dili"), selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.displayName).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text(verbatim: text("Dil"))
            } footer: {
                Text(verbatim: text("Dil değişikliği uygulamanın tamamına hemen uygulanır."))
            }
        }
        .formStyle(.grouped)
    }

    private var assistantSettings: some View {
        Form {
            apiKeySection
            modelSection
            reasoningSection
            responseSection
            samplingSection
            requestSection
            managedSection

            if !message.isEmpty {
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var apiKeySection: some View {
        Section {
            LabeledContent(text("API anahtarı")) {
                SecureField("sk-…", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                    .privacySensitive()
                    .accessibilityLabel(text("OpenAI API anahtarı"))
            }

            HStack {
                Label(
                    text(hasStoredKey ? "API anahtarı bu Mac’te yerel olarak saklanıyor." : "Henüz bir API anahtarı kaydedilmedi."),
                    systemImage: hasStoredKey ? "checkmark.shield.fill" : "key.slash"
                )
                .font(.caption)
                .foregroundStyle(hasStoredKey ? Color.green : Color.secondary)
                Spacer()
                if hasStoredKey {
                    Button(text("Anahtarı Sil"), role: .destructive) {
                        OpenAIAPIKeyStore.delete()
                        apiKey = ""
                        savedAPIKey = ""
                        hasOpenAIAPIKey = false
                        message = text("API anahtarı silindi.")
                    }
                }
                Button(text("Kaydet")) { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
        } header: {
            Text("OpenAI")
        } footer: {
            Text(verbatim: text("Ses kayıtlarını dönüştürmek ve Analiz Asistanı ile sohbet etmek için kullanılır. Anahtar Keychain’de tutulur; proje dosyasına veya yedeklere eklenmez."))
        }
    }

    private var modelSection: some View {
        Section {
            Picker(text("Analiz modeli"), selection: $analysisModel) {
                ForEach(modelOptions, id: \.self) { modelID in
                    Text(verbatim: AnalysisModelCatalog.displayName(for: modelID)).tag(modelID)
                }
            }
            HStack {
                Label(text("Model listesi OpenAI hesabınızdan alınır."), systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isRefreshingModels { ProgressView().controlSize(.small) }
                Button(text("Modelleri Yenile")) {
                    Task { await refreshModels(force: true) }
                }
                .disabled(!hasStoredKey || isRefreshingModels)
            }
            if !modelMessage.isEmpty {
                Text(verbatim: modelMessage).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text(verbatim: text("Model"))
        } footer: {
            Text(verbatim: text("Model listesi API hesabınızdan gelir. Parametre desteği model ailesine göre otomatik uyarlanır."))
        }
    }

    @ViewBuilder
    private var reasoningSection: some View {
        if capabilities.supportsReasoning {
            Section(text("Düşünme")) {
                Picker(text("Düşünme düzeyi"), selection: $reasoningEffort) {
                    Text(verbatim: OpenAISettingLabels.reasoningEffort("auto")).tag("auto")
                    ForEach(capabilities.reasoningEfforts, id: \.self) { value in
                        Text(verbatim: OpenAISettingLabels.reasoningEffort(value)).tag(value)
                    }
                }
                if capabilities.supportsReasoningMode {
                    settingPicker(text("Düşünme modu"), values: ["standard", "pro"], selection: $reasoningMode)
                }
                settingPicker(text("Geçmiş düşünme bağlamı"), values: capabilities.reasoningContexts, selection: $reasoningContext)
                settingPicker(text("Düşünme özeti"), values: ["none", "auto", "concise", "detailed"], selection: $reasoningSummary)
            }
        }
    }

    private var responseSection: some View {
        Section(text("Yanıt")) {
            if capabilities.supportsVerbosity {
                settingPicker(text("Yanıt ayrıntısı"), values: ["low", "medium", "high"], selection: $responseVerbosity)
            }
            Stepper(value: $maxOutputTokens, in: 1_000...capabilities.maximumOutputTokens, step: 1_000) {
                LabeledContent(text("En fazla çıktı tokenı"), value: maxOutputTokens.formatted())
            }
        }
    }

    private var samplingSection: some View {
        Section {
            if samplingAvailable {
                Toggle(text("Temperature kullan"), isOn: $temperatureEnabled)
                if temperatureEnabled { valueSlider(text("Temperature"), value: $temperature, range: 0...2) }
                Toggle(text("Top P kullan"), isOn: $topPEnabled)
                if topPEnabled { valueSlider(text("Top P"), value: $topP, range: 0...1) }
                Toggle(text("Token olasılıklarını iste"), isOn: $topLogprobsEnabled)
                if topLogprobsEnabled {
                    Stepper(value: $topLogprobs, in: 0...20) {
                        LabeledContent(text("Top logprobs"), value: topLogprobs.formatted())
                    }
                }
            } else {
                Label(text("Temperature, Top P ve logprobs yalnızca düşünme düzeyi ‘Yok’ olduğunda kullanılabilir."), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(verbatim: text("Örnekleme"))
        } footer: {
            Text(verbatim: text("OpenAI, Temperature veya Top P’den yalnızca birini değiştirmenizi önerir."))
        }
    }

    private var requestSection: some View {
        Section(text("İstek ve işleme")) {
            settingPicker(text("Hizmet katmanı"), values: capabilities.serviceTiers, selection: $serviceTier)
            Picker(text("Bağlam taşması"), selection: $truncation) {
                Text(verbatim: text("Eski mesajları otomatik kırp")).tag("auto")
                Text(verbatim: OpenAISettingLabels.generic("disabled")).tag("disabled")
            }
            if capabilities.supportsPromptCaching {
                Toggle(text("İstem önbelleğini kullan"), isOn: $promptCachingEnabled)
                if promptCachingEnabled {
                    settingPicker(text("Önbellek modu"), values: ["implicit", "explicit"], selection: $promptCacheMode)
                }
            }
            DisclosureGroup(text("İçerik denetimi")) {
                settingPicker(text("Girdi"), values: ["off", "score", "block"], selection: $inputModeration)
                settingPicker(text("Çıktı"), values: ["off", "score", "block"], selection: $outputModeration)
            }
        }
    }

    private var managedSection: some View {
        Section(text("Uygulama tarafından yönetilen")) {
            LabeledContent(text("Yanıt saklama"), value: text("Kapalı (store: false)"))
            LabeledContent(text("Çıktı biçimi"), value: text("Yapılandırılmış JSON"))
            LabeledContent(text("Akış"), value: text("Devre dışı"))
            Text(verbatim: text("Bu alanlar gizlilik ve tablo/grafik görünümünün bozulmaması için değiştirilemez."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func settingPicker(_ title: String, values: [String], selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(values, id: \.self) { value in
                Text(verbatim: OpenAISettingLabels.generic(value)).tag(value)
            }
        }
    }

    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
            Slider(value: value, in: range, step: 0.05)
        }
    }

    private func text(_ source: String) -> String {
        AppLocalization.string(source)
    }

    private var modelOptions: [String] {
        var seen: Set<String> = []
        return (availableModels + [analysisModel])
            .filter { seen.insert($0).inserted }
    }

    private func reload() {
        let stored = OpenAIAPIKeyStore.load()
        apiKey = stored
        savedAPIKey = stored
        hasOpenAIAPIKey = !stored.isEmpty
    }

    private func save() {
        do {
            try OpenAIAPIKeyStore.save(apiKey)
            reload()
            message = text("API anahtarı güvenli biçimde kaydedildi.")
        } catch {
            message = "\(text("API anahtarı kaydedilemedi:")) \(error.localizedDescription)"
        }
    }

    private func loadCachedModels() {
        guard let data = UserDefaults.standard.data(forKey: "openAIAnalysisModels"),
              let cached = try? JSONDecoder().decode([String].self, from: data),
              !cached.isEmpty else { return }
        let cachedModels = cached.map { OpenAIAnalysisModel(id: $0, created: nil, ownedBy: nil) }
        let compatible = AnalysisModelCatalog.compatibleModelIDs(from: cachedModels)
        if !compatible.isEmpty { availableModels = compatible }
    }

    @MainActor
    private func refreshModels(force: Bool) async {
        guard hasStoredKey else { return }
        let lastRefresh = UserDefaults.standard.object(forKey: "openAIAnalysisModelsRefreshedAt") as? Date
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 24 * 60 * 60 { return }

        isRefreshingModels = true
        defer { isRefreshingModels = false }
        do {
            let models = try await OpenAIAnalysisAssistantService.listModels(apiKey: savedAPIKey)
            let compatible = AnalysisModelCatalog.compatibleModelIDs(from: models)
            guard !compatible.isEmpty else { throw OpenAIAnalysisAssistantError.noCompatibleModel }
            availableModels = compatible
            UserDefaults.standard.set(try JSONEncoder().encode(compatible), forKey: "openAIAnalysisModels")
            UserDefaults.standard.set(Date(), forKey: "openAIAnalysisModelsRefreshedAt")
            if !compatible.contains(analysisModel) {
                analysisModel = AnalysisModelCatalog.recommendedModelIDs.first(where: compatible.contains) ?? compatible[0]
            }
            reconcileSettings()
            modelMessage = AppLocalization.language == .english
                ? "\(compatible.count) compatible models found."
                : "\(compatible.count) uyumlu model bulundu."
        } catch {
            modelMessage = "\(text("Model listesi yenilenemedi:")) \(error.localizedDescription)"
        }
    }

    private func reconcileSettings() {
        let profile = OpenAIModelCapabilityCatalog.capabilities(for: analysisModel)
        if reasoningEffort != "auto", !profile.reasoningEfforts.contains(reasoningEffort) {
            reasoningEffort = "auto"
        }
        if !profile.reasoningContexts.contains(reasoningContext) {
            reasoningContext = profile.reasoningContexts.first ?? "auto"
        }
        if !profile.serviceTiers.contains(serviceTier) {
            serviceTier = "auto"
        }
        maxOutputTokens = min(max(maxOutputTokens, 1_000), profile.maximumOutputTokens)
        if !profile.supportsSampling(for: reasoningEffort) {
            temperatureEnabled = false
            topPEnabled = false
            topLogprobsEnabled = false
        }
    }
}
