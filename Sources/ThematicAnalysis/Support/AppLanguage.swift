import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case turkish = "tr"
    case english = "en"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    var displayName: String {
        switch self {
        case .turkish: "Türkçe"
        case .english: "English"
        }
    }
}

enum AppLocalization {
    static let languageKey = "appLanguage"
    private static let englishDefaultMigrationKey = "englishDefaultLanguageMigrationVersion"
    private static let englishDefaultMigrationVersion = 1

    static func applyEnglishDefaultMigrationIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.integer(forKey: englishDefaultMigrationKey) < englishDefaultMigrationVersion else { return }
        defaults.set(AppLanguage.english.rawValue, forKey: languageKey)
        defaults.set(englishDefaultMigrationVersion, forKey: englishDefaultMigrationKey)
    }

    static var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: languageKey) ?? AppLanguage.english.rawValue) ?? .english
    }

    static func string(_ source: String) -> String {
        guard language == .english,
              let path = Bundle.module.path(forResource: "en", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return source }

        let localized = bundle.localizedString(forKey: source, value: source, table: nil)
        if localized != source { return localized }

        var result = source
        let replacements: [(String, String)] = [
            ("İçe aktarma başarısız: ", "Import failed: "),
            ("Katılımcı eklenemedi: ", "Could not add participant: "),
            ("Tema listesi içe aktarılamadı: ", "Could not import theme list: "),
            ("Yedek oluşturulamadı: ", "Could not create backup: "),
            ("Excel çıktısı kaydedildi: ", "Excel export saved: "),
            ("Excel çıktısı oluşturulamadı: ", "Could not create Excel export: "),
            ("Tablo dışa aktarıldı: ", "Table exported: "),
            ("Dışa aktarma hatası: ", "Export failed: "),
            ("Proje arşivi oluşturuldu: ", "Project archive created: "),
            ("Arşiv oluşturulamadı: ", "Could not create archive: "),
            ("Ses transkripsiyonu başarısız: ", "Audio transcription failed: "),
            ("Tam yedek oluşturuldu: ", "Full backup created: "),
            ("Yedek açılamadı: ", "Could not open backup: "),
            ("Yedek oluşturuldu: ", "Backup created: "),
            ("Kaydetme hatası: ", "Save failed: "),
            ("API anahtarı kaydedilemedi: ", "Could not save API key: "),
            ("Sürüm ", "Version "),
            ("Sütunlar (", "Columns ("),
            (" satır tek satırda birleştirildi", " rows merged into one row"),
            (" transkript satırı silindi", " transcript row(s) deleted"),
            (" satırlık GPT transkripsiyonu eklendi", " GPT transcript row(s) added"),
            (" zamanlı ve konuşmacılı satır eklendi", " timed, speaker-labeled row(s) added"),
            (" tema düğümü içe aktarıldı", " theme node(s) imported"),
            (" teması eklendi", " theme added"),
            (" bilgileri güncellendi", " details updated"),
            (" için ", " — "),
            (" proje", " project(s)"),
            (" katılımcı", " participant(s)"),
            (" kodlama birimi", " coding unit(s)"),
            (" kodlama görünümü", " coding occurrence(s)"),
            (" kodlama", " coding item(s)"),
            (" transkript satırı", " transcript row(s)"),
            (" satır", " row(s)"),
            (" tema düğümü", " theme node(s)"),
            (" tema", " theme(s)"),
            (" görünüm", " occurrence(s)"),
            (" matris puanı", " matrix score"),
            (" günlük kaydı", " journal entry/entries"),
            (" tema taslağı", " theme draft(s)"),
            (" destekleyici alıntı", " supporting excerpt(s)"),
            (" karşıt alıntı", " contradictory excerpt(s)"),
            (" karşıt", " contradictory"),
            (" koddan geliştirildi", " code(s) developed into this theme"),
            (" farklı katılımcıya dayanıyor", " participants represented"),
            (" alıntı", " excerpt(s)"),
            (" kanıt", " evidence item(s)"),
            (" kod", " code(s)"),
            (" eklendi", " added"),
            (" içe aktarıldı", " imported"),
            (" güncellendi", " updated"),
            (" kaydedildi", " saved"),
            (" kaldırıldı", " removed"),
            (" silindi", " deleted")
        ]
        for (turkish, english) in replacements {
            result = result.replacingOccurrences(of: turkish, with: english)
        }
        return result
    }
}
