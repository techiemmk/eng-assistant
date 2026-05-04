import Foundation

public struct TextMetrics: Equatable, Sendable {
    public let totalWordCount: Int
    public let uniqueWordCount: Int
    public let fillerCount: Int
    public var uniqueWordRatio: Double {
        guard totalWordCount > 0 else { return 0 }
        return Double(uniqueWordCount) / Double(totalWordCount)
    }
    public var fillerDensity: Double {
        guard totalWordCount > 0 else { return 0 }
        return Double(fillerCount) / Double(totalWordCount)
    }

    public init(totalWordCount: Int, uniqueWordCount: Int, fillerCount: Int) {
        self.totalWordCount = totalWordCount
        self.uniqueWordCount = uniqueWordCount
        self.fillerCount = fillerCount
    }
}

public enum TextMetricsCalculator {
    public static func calculate(text: String) -> TextMetrics {
        let words = tokenize(text)
        guard !words.isEmpty else {
            return TextMetrics(totalWordCount: 0, uniqueWordCount: 0, fillerCount: 0)
        }
        let unique = Set(words)
        let fillerCount = countFillers(in: words)
        return TextMetrics(
            totalWordCount: words.count,
            uniqueWordCount: unique.count,
            fillerCount: fillerCount
        )
    }

    /// Lowercase, split on whitespace, strip surrounding punctuation. We don't
    /// strip in-word apostrophes ("don't", "I'm") — fluency analysis depends on them.
    private static func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let punctuation = CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'"))
        return lowered
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: punctuation) }
            .filter { !$0.isEmpty }
    }

    private static func countFillers(in words: [String]) -> Int {
        var count = 0
        var i = 0
        while i < words.count {
            // Try phrase fillers first (longest match).
            var matchedPhraseLength = 0
            for phrase in FillerDictionary.phrases {
                if i + phrase.count <= words.count,
                   Array(words[i..<i + phrase.count]) == phrase {
                    matchedPhraseLength = max(matchedPhraseLength, phrase.count)
                }
            }
            if matchedPhraseLength > 0 {
                count += 1
                i += matchedPhraseLength
                continue
            }
            if FillerDictionary.singleWord.contains(words[i]) {
                count += 1
            }
            i += 1
        }
        return count
    }
}
