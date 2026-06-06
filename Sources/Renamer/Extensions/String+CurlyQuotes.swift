import Foundation

extension String {
    /// Replaces straight quotes (" and ') with typographic curly quotes (" " and ' ').
    /// Uses the preceding character to decide opening vs. closing:
    ///   - preceded by a letter or digit  →  closing quote (" or ')
    ///   - preceded by space / start / other  →  opening quote (" or ')
    func curlyQuoted() -> String {
        var result = ""
        result.reserveCapacity(self.count)

        for (index, char) in self.enumerated() {
            guard char == "\"" || char == "'" else {
                result.append(char)
                continue
            }

            // Look at the character immediately before this one
            let prevChar: Character? = index > 0 ? self[self.index(self.startIndex, offsetBy: index - 1)] : nil
            let isClosing = prevChar.map { $0.isLetter || $0.isNumber } ?? false

            switch char {
            case "\"":
                result.append(isClosing ? "\u{201D}" : "\u{201C}")  // " or "
            case "'":
                result.append(isClosing ? "\u{2019}" : "\u{2018}")  // ' or '
            default:
                result.append(char)
            }
        }

        return result
    }
}
