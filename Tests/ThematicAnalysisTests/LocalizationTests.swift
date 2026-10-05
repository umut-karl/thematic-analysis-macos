import Foundation
import XCTest
@testable import ThematicAnalysis

final class LocalizationTests: XCTestCase {
    func testEnglishLocalizesCoreNavigationAndActions() {
        withLanguage(.english) {
            XCTAssertEqual(AppLocalization.string("Katılımcılar"), "Participants")
            XCTAssertEqual(AppLocalization.string("Kodlanmış Alıntılar"), "Coded Excerpts")
            XCTAssertEqual(AppLocalization.string("Tema Haritası"), "Theme Map")
            XCTAssertEqual(AppLocalization.string("Analiz Asistanı"), "Analysis Assistant")
            XCTAssertEqual(AppLocalization.string("Sohbetler"), "Chats")
            XCTAssertEqual(AppLocalization.string("Kaydedilen Analizler"), "Saved Analyses")
            XCTAssertEqual(AppLocalization.string("Ayarlar"), "Settings")
            XCTAssertEqual(AppLocalization.string("Kaydet ve Kodlamayı Bitir"), "Save and Finish Coding")
        }
    }

    func testEnglishLocalizesDynamicStatusMessages() {
        withLanguage(.english) {
            XCTAssertEqual(AppLocalization.string("12 satır içe aktarıldı"), "12 row(s) imported")
            XCTAssertEqual(AppLocalization.string("1 proje"), "1 project(s)")
            XCTAssertEqual(
                AppLocalization.string("Excel çıktısı kaydedildi: interview.xlsx"),
                "Excel export saved: interview.xlsx"
            )
        }
    }

    func testFirstRunMigrationSelectsEnglish() throws {
        let suiteName = "TematikAnaliz-Localization-Tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppLanguage.turkish.rawValue, forKey: AppLocalization.languageKey)
        AppLocalization.applyEnglishDefaultMigrationIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppLocalization.languageKey), AppLanguage.english.rawValue)
    }

    func testEnglishLocalizesAssistantSettingsAndSuggestions() {
        withLanguage(.english) {
            XCTAssertEqual(AppLocalization.string("Düşünme düzeyi"), "Reasoning effort")
            XCTAssertEqual(AppLocalization.string("Model varsayılanı"), "Model default")
            XCTAssertEqual(AppLocalization.string("Yanıt ayrıntısı"), "Response verbosity")
            XCTAssertEqual(AppLocalization.string("İstek ve işleme"), "Request and Processing")
            XCTAssertEqual(AppLocalization.string("Verilerle konuş"), "Talk with the data")
            XCTAssertEqual(AppLocalization.string("Analiz Bağlamı"), "Analysis Context")
            XCTAssertEqual(AppLocalization.string("Bağlam"), "Context")
            XCTAssertEqual(AppLocalization.string("Bağlamı Aç"), "Open Context")
            XCTAssertEqual(AppLocalization.string("Bağlam: Belirlendi"), "Context: Set")
            XCTAssertEqual(AppLocalization.string("Bağlam: Belirlenmedi"), "Context: Not set")
            XCTAssertEqual(AppLocalization.string("Araştırmacı kararı"), "Researcher decision")
            XCTAssertEqual(AppLocalization.string("istem"), "prompt")
            XCTAssertEqual(
                AppLocalization.string("En güçlü temalar ve bunları destekleyen kanıtlar neler?"),
                "What are the strongest themes and the evidence supporting them?"
            )
        }
    }

    func testTurkishKeepsSourceCopy() {
        withLanguage(.turkish) {
            XCTAssertEqual(AppLocalization.string("Katılımcılar"), "Katılımcılar")
            XCTAssertEqual(AppLocalization.string("Bağlam: Belirlendi"), "Bağlam: Belirlendi")
            XCTAssertEqual(AppLocalization.string("Bağlam: Belirlenmedi"), "Bağlam: Belirlenmedi")
        }
    }

    private func withLanguage(_ language: AppLanguage, assertions: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "appLanguage")
        defaults.set(language.rawValue, forKey: "appLanguage")
        defer {
            if let previous { defaults.set(previous, forKey: "appLanguage") }
            else { defaults.removeObject(forKey: "appLanguage") }
        }
        assertions()
    }
}
