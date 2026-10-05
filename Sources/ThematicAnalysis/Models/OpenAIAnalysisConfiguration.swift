import Foundation

struct OpenAIModelCapabilities: Equatable {
    let reasoningEfforts: [String]
    let defaultReasoningEffort: String?
    let supportsReasoningMode: Bool
    let reasoningContexts: [String]
    let supportsReasoningSummary: Bool
    let supportsVerbosity: Bool
    let supportsPromptCaching: Bool
    let maximumOutputTokens: Int
    let serviceTiers: [String]

    var supportsReasoning: Bool { !reasoningEfforts.isEmpty }

    func supportsSampling(for selectedEffort: String) -> Bool {
        guard supportsReasoning else { return true }
        let effectiveEffort = selectedEffort == "auto" ? defaultReasoningEffort : selectedEffort
        return effectiveEffort == "none"
    }
}

enum OpenAIModelCapabilityCatalog {
    static func capabilities(for modelID: String) -> OpenAIModelCapabilities {
        let id = modelID.lowercased()
        let serviceTiers = ["auto", "default", "flex", "scale", "priority", "fast"]

        if id.hasPrefix("gpt-4") {
            return .init(
                reasoningEfforts: [],
                defaultReasoningEffort: nil,
                supportsReasoningMode: false,
                reasoningContexts: [],
                supportsReasoningSummary: false,
                supportsVerbosity: false,
                supportsPromptCaching: true,
                maximumOutputTokens: 32_768,
                serviceTiers: serviceTiers
            )
        }

        let isGPT61Sol = id.hasPrefix("gpt-6.1-sol")
        let isGPT6Astra = id.hasPrefix("gpt-6-astra")
        let isGPT6SolOrLuna = id.hasPrefix("gpt-6-sol") || id.hasPrefix("gpt-6-luna")
        let isGPT56 = id.hasPrefix("gpt-5.6")
        let isGPT55 = id.hasPrefix("gpt-5.5")
        let isGPT54 = id.hasPrefix("gpt-5.4")

        let efforts: [String]
        let defaultEffort: String
        if isGPT61Sol || isGPT6Astra {
            efforts = ["low", "medium", "high", "xhigh", "max"]
            defaultEffort = "medium"
        } else if isGPT6SolOrLuna || isGPT56 {
            efforts = ["none", "low", "medium", "high", "xhigh", "max"]
            defaultEffort = "medium"
        } else if isGPT55 {
            efforts = ["none", "low", "medium", "high", "xhigh"]
            defaultEffort = "medium"
        } else if isGPT54 {
            efforts = ["none", "low", "medium", "high", "xhigh"]
            defaultEffort = "none"
        } else {
            // The Models API does not publish parameter capabilities. New GPT
            // families receive the broad Responses API set until their exact
            // profile is added to this catalog.
            efforts = ["none", "minimal", "low", "medium", "high", "xhigh", "max"]
            defaultEffort = "medium"
        }

        let supportsProMode = isGPT56 || id.hasPrefix("gpt-6")
        let supportsAllTurns = isGPT56 || isGPT61Sol
        let tiers = id.hasPrefix("gpt-5.6-sol") ? serviceTiers + ["ultrafast"] : serviceTiers

        return .init(
            reasoningEfforts: efforts,
            defaultReasoningEffort: defaultEffort,
            supportsReasoningMode: supportsProMode,
            reasoningContexts: supportsAllTurns ? ["auto", "current_turn", "all_turns"] : ["auto", "current_turn"],
            supportsReasoningSummary: true,
            supportsVerbosity: true,
            supportsPromptCaching: isGPT56 || id.hasPrefix("gpt-6"),
            maximumOutputTokens: 128_000,
            serviceTiers: tiers
        )
    }
}

struct OpenAIAnalysisConfiguration: Equatable {
    let modelID: String
    let reasoningEffort: String
    let reasoningMode: String
    let reasoningContext: String
    let reasoningSummary: String
    let verbosity: String
    let maxOutputTokens: Int
    let temperatureEnabled: Bool
    let temperature: Double
    let topPEnabled: Bool
    let topP: Double
    let topLogprobsEnabled: Bool
    let topLogprobs: Int
    let serviceTier: String
    let truncation: String
    let promptCachingEnabled: Bool
    let promptCacheMode: String
    let inputModeration: String
    let outputModeration: String

    static func defaults(modelID: String) -> Self {
        .init(
            modelID: modelID,
            reasoningEffort: "auto",
            reasoningMode: "standard",
            reasoningContext: "auto",
            reasoningSummary: "none",
            verbosity: "medium",
            maxOutputTokens: 6_000,
            temperatureEnabled: false,
            temperature: 1,
            topPEnabled: false,
            topP: 1,
            topLogprobsEnabled: false,
            topLogprobs: 0,
            serviceTier: "auto",
            truncation: "disabled",
            promptCachingEnabled: true,
            promptCacheMode: "implicit",
            inputModeration: "off",
            outputModeration: "off"
        )
    }

    static func load(modelID: String, defaults: UserDefaults = .standard) -> Self {
        let baseline = Self.defaults(modelID: modelID)
        return .init(
            modelID: modelID,
            reasoningEffort: defaults.string(forKey: "openAIReasoningEffort") ?? baseline.reasoningEffort,
            reasoningMode: defaults.string(forKey: "openAIReasoningMode") ?? baseline.reasoningMode,
            reasoningContext: defaults.string(forKey: "openAIReasoningContext") ?? baseline.reasoningContext,
            reasoningSummary: defaults.string(forKey: "openAIReasoningSummary") ?? baseline.reasoningSummary,
            verbosity: defaults.string(forKey: "openAIResponseVerbosity") ?? baseline.verbosity,
            maxOutputTokens: defaults.object(forKey: "openAIMaxOutputTokens") as? Int ?? baseline.maxOutputTokens,
            temperatureEnabled: defaults.bool(forKey: "openAITemperatureEnabled"),
            temperature: defaults.object(forKey: "openAITemperature") as? Double ?? baseline.temperature,
            topPEnabled: defaults.bool(forKey: "openAITopPEnabled"),
            topP: defaults.object(forKey: "openAITopP") as? Double ?? baseline.topP,
            topLogprobsEnabled: defaults.bool(forKey: "openAITopLogprobsEnabled"),
            topLogprobs: defaults.object(forKey: "openAITopLogprobs") as? Int ?? baseline.topLogprobs,
            serviceTier: defaults.string(forKey: "openAIServiceTier") ?? baseline.serviceTier,
            truncation: defaults.string(forKey: "openAITruncation") ?? baseline.truncation,
            promptCachingEnabled: defaults.object(forKey: "openAIPromptCachingEnabled") as? Bool ?? true,
            promptCacheMode: defaults.string(forKey: "openAIPromptCacheMode") ?? baseline.promptCacheMode,
            inputModeration: defaults.string(forKey: "openAIInputModeration") ?? baseline.inputModeration,
            outputModeration: defaults.string(forKey: "openAIOutputModeration") ?? baseline.outputModeration
        )
    }
}

enum OpenAISettingLabels {
    static func reasoningEffort(_ value: String) -> String {
        let source = switch value {
        case "auto": "Model varsayılanı"
        case "none": "Yok"
        case "minimal": "En az"
        case "low": "Düşük"
        case "medium": "Orta"
        case "high": "Yüksek"
        case "xhigh": "Çok yüksek"
        case "max": "Maksimum"
        default: value
        }
        return AppLocalization.string(source)
    }

    static func generic(_ value: String) -> String {
        let source = switch value {
        case "auto": "Otomatik"
        case "default": "Standart hizmet"
        case "standard": "Standart"
        case "pro": "Pro"
        case "current_turn": "Yalnızca güncel tur"
        case "all_turns": "Tüm turlar"
        case "none": "Yok"
        case "concise": "Kısa"
        case "detailed": "Ayrıntılı"
        case "low": "Düşük"
        case "medium": "Orta"
        case "high": "Yüksek"
        case "disabled": "Taşarsa hata ver"
        case "implicit": "Otomatik önbellek noktası"
        case "explicit": "Yalnızca açık noktalar"
        case "score": "Puanla"
        case "block": "Engelle"
        case "off": "Devre dışı"
        case "flex": "Flex"
        case "scale": "Scale"
        case "priority": "Öncelikli"
        case "fast": "Hızlı"
        case "ultrafast": "Ultra hızlı"
        default: value.capitalized
        }
        return AppLocalization.string(source)
    }
}
