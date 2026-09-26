import Foundation

/// Herdr strips known spinner glyphs from titles but not the quadrant circles newer
/// Claude Code cycles through; this mirrors Herdr's rule (`src/terminal/title.rs`).
enum ActivityGlyph {
    private static let glyphs: Set<Character> = [
        "\u{00B7}", "\u{2722}", "\u{2733}", "\u{2736}", "\u{273B}", "\u{273D}",
        "\u{25D0}", "\u{25D1}", "\u{25D2}", "\u{25D3}",
    ]
    private static let brailleRange = 0x2800...0x28FF

    static func stripLeading(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, isActivityGlyph(first) else { return trimmed }

        let rest = trimmed.dropFirst()
        guard rest.isEmpty || rest.first?.isWhitespace == true else { return trimmed }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    private static func isActivityGlyph(_ character: Character) -> Bool {
        let isBraille = character.unicodeScalars.first
            .map { brailleRange.contains(Int($0.value)) } ?? false
        return isBraille || glyphs.contains(character)
    }
}
