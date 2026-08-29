import Foundation

enum DefaultThemeCatalog {
    static var nodes: [ThemeNode] {
        guard let url = Bundle.module.url(forResource: "DefaultThemes", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return ThemeMarkdownImporter.parse(markdown)
    }
}
