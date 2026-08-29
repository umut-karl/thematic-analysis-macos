import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    var displayName: String {
        "English"
    }
}

enum AppLocalization {
    static var language: AppLanguage {
        .english
    }

    static func string(_ source: String) -> String {
        source
    }
}
