import SwiftUI

struct SettingsView: View {
    @AppStorage("hasOpenAIAPIKey") private var hasOpenAIAPIKey = false
    @State private var apiKey = ""
    @State private var savedAPIKey = ""
    @State private var message = ""

    private var hasStoredKey: Bool {
        !savedAPIKey.isEmpty
    }

    private var canSave: Bool {
        let clean = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !clean.isEmpty && clean != savedAPIKey
    }

    var body: some View {
        Form {
            Section {
                SecureField("sk-…", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .privacySensitive()
                    .accessibilityLabel("OpenAI API key")

                HStack {
                    Label {
                        Text(LocalizedStringKey(hasStoredKey ? "The API key is stored locally on this Mac." : "No API key has been saved yet."))
                    } icon: {
                        Image(systemName: hasStoredKey ? "checkmark.shield.fill" : "key.slash")
                    }
                    .font(.caption)
                    .foregroundStyle(hasStoredKey ? Color.green : Color.secondary)

                    Spacer()

                    if hasStoredKey {
                        Button("Delete Key", role: .destructive) {
                            OpenAIAPIKeyStore.delete()
                            apiKey = ""
                            savedAPIKey = ""
                            hasOpenAIAPIKey = false
                            message = "API key deleted."
                        }
                    }
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
                }
            } header: {
                Text("OpenAI")
            } footer: {
                Text("Used to transcribe audio with timestamps and speaker information. The key is stored in this Mac's app settings and is not included in project files or backups.")
            }

            if !message.isEmpty {
                Text(LocalizedStringKey(message))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 330)
        .navigationTitle(AppLocalization.string("Settings"))
        .task { reload() }
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
            message = "API key saved securely."
        } catch {
            message = "Could not save API key: \(error.localizedDescription)"
        }
    }
}
