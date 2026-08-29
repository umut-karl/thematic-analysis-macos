import SwiftUI

enum SpeakerPalette {
    struct Swatch {
        let accentHex: String
        let backgroundHex: String

        var color: Color {
            Color(rgbHex: accentHex)
        }

        var backgroundARGB: String { "FF\(backgroundHex)" }
    }

    static let swatches: [Swatch] = [
        Swatch(accentHex: "2563EB", backgroundHex: "EAF2FF"),
        Swatch(accentHex: "E66A12", backgroundHex: "FFF0E6"),
        Swatch(accentHex: "168A47", backgroundHex: "E8F7EE"),
        Swatch(accentHex: "7C4DCC", backgroundHex: "F2EBFF"),
        Swatch(accentHex: "C43D69", backgroundHex: "FFEAF1"),
        Swatch(accentHex: "087F78", backgroundHex: "E5F7F5"),
        Swatch(accentHex: "9A6A00", backgroundHex: "FFF6D8"),
        Swatch(accentHex: "4F5FC7", backgroundHex: "ECEEFF")
    ]

    static func indices(for speakers: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for speaker in speakers {
            let key = normalized(speaker)
            guard !key.isEmpty, key != "—", result[key] == nil else { continue }
            result[key] = result.count % swatches.count
        }
        return result
    }

    static func index(for speaker: String, in indices: [String: Int]) -> Int? {
        indices[normalized(speaker)]
    }

    static func color(_ index: Int) -> Color {
        swatches[index % swatches.count].color
    }

    private static func normalized(_ speaker: String) -> String {
        speaker.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Color {
    init(rgbHex: String) {
        let value = UInt64(rgbHex, radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
