import AppKit
import SwiftUI

@main
struct ThematicAnalysisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library: ProjectLibraryStore
    @AppStorage(AppLocalization.languageKey) private var appLanguage = AppLanguage.english.rawValue

    init() {
        AppLocalization.applyEnglishDefaultMigrationIfNeeded()
        _library = StateObject(wrappedValue: ProjectLibraryStore())
    }

    private var locale: Locale {
        AppLanguage(rawValue: appLanguage)?.locale ?? AppLanguage.english.locale
    }

    var body: some Scene {
        WindowGroup(AppLocalization.string("Tematik Analiz"), id: "main") {
            AppRootView(library: library)
                .frame(minWidth: 980, minHeight: 640)
                .environment(\.locale, locale)
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button { library.isCreatingProject = true } label: {
                    Text(verbatim: AppLocalization.string("Yeni Proje…"))
                }
                    .keyboardShortcut("n", modifiers: .command)
                Button { library.closeProject() } label: {
                    Text(verbatim: AppLocalization.string("Proje Kütüphanesi"))
                }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
                Button { library.activeProjectStore?.persist() } label: {
                    Text(verbatim: AppLocalization.string("Şimdi Kaydet"))
                }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(library.activeProjectStore == nil)
                Button { library.activeProjectStore?.createBackup() } label: {
                    Text(verbatim: AppLocalization.string("Yedek Oluştur"))
                }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(library.activeProjectStore == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(\.locale, locale)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
