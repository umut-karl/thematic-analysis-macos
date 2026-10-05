import Foundation

enum ThemeMarkdownImporter {
    static func parse(_ markdown: String) -> [ThemeNode] {
        var result: [ThemeNode] = []
        var stack: [(level: Int, id: UUID)] = []
        var rootColor = -1

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "\r", with: "")
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "# Temalar" else { continue }

            let level: Int
            let name: String
            if trimmed.hasPrefix("### ") {
                level = 1
                name = clean(String(trimmed.dropFirst(4)))
            } else if trimmed.hasPrefix("## ") {
                level = 0
                name = clean(String(trimmed.dropFirst(3)))
            } else if let bullet = bulletContent(line) {
                level = 2 + bullet.indent
                name = clean(bullet.text)
            } else {
                continue
            }
            guard !name.isEmpty else { continue }

            while let last = stack.last, last.level >= level { stack.removeLast() }
            let parentID = stack.last?.id
            if level == 0 { rootColor += 1 }
            let color = parentID.flatMap { id in result.first(where: { $0.id == id })?.colorIndex } ?? max(rootColor, 0)
            let node = ThemeNode(name: name, parentID: parentID, colorIndex: color)
            result.append(node)
            stack.append((level, node.id))
        }
        return result
    }

    private static func bulletContent(_ line: String) -> (indent: Int, text: String)? {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(leading.count)
        guard rest.hasPrefix("- ") else { return nil }
        let tabs = leading.filter { $0 == "\t" }.count
        let spaces = leading.filter { $0 == " " }.count
        return (tabs + spaces / 2, String(rest.dropFirst(2)))
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
