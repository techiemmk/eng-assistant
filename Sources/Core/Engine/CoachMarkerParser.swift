import Foundation

public struct Correction: Equatable, Sendable {
    public let message: String
    /// What kind of mistake this is, when the model labelled it
    /// (`[[coach:grammar: ...]]`). `nil` for an unlabelled marker.
    public let category: WeakSpotCategory?
    /// The user's own wrong wording, pulled out of the message so the UI can
    /// highlight it inside the transcript instead of only printing advice
    /// underneath it. `nil` when the message doesn't quote one.
    public let offendingText: String?

    public init(message: String, category: WeakSpotCategory? = nil, offendingText: String? = nil) {
        self.message = message
        self.category = category
        self.offendingText = offendingText
    }
}

public struct ParsedReply: Equatable, Sendable {
    public let spokenText: String
    public let corrections: [Correction]

    public init(spokenText: String, corrections: [Correction]) {
        self.spokenText = spokenText
        self.corrections = corrections
    }
}

public enum CoachMarkerParser {
    private static let openMarker = "[[coach:"
    private static let closeMarker = "]]"

    public static func parse(_ input: String) -> ParsedReply {
        var spoken = ""
        var corrections: [Correction] = []
        var remaining = input[...]

        while let openRange = remaining.range(of: openMarker) {
            spoken += remaining[..<openRange.lowerBound]
            let afterOpen = remaining[openRange.upperBound...]
            guard let closeRange = afterOpen.range(of: closeMarker) else {
                spoken += remaining[openRange.lowerBound...]
                return ParsedReply(spokenText: spoken, corrections: corrections)
            }
            let body = afterOpen[..<closeRange.lowerBound]
            corrections.append(correction(fromMarkerBody: body))
            remaining = afterOpen[closeRange.upperBound...]
        }
        spoken += remaining
        return ParsedReply(spokenText: spoken, corrections: corrections)
    }

    // MARK: - private

    /// Splits an optional `<category>:` label off the front of the marker body,
    /// then mines the remaining message for the phrase being corrected.
    private static func correction(fromMarkerBody body: Substring) -> Correction {
        var message = body.trimmingCharacters(in: .whitespaces)
        var category: WeakSpotCategory?

        if let colon = message.firstIndex(of: ":") {
            let label = message[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            if let parsed = WeakSpotCategory(rawValue: label) {
                category = parsed
                message = message[message.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        return Correction(
            message: message,
            category: category,
            offendingText: offendingText(in: message)
        )
    }

    /// The persona prompt asks for "try 'X' instead of 'Y'" for a substitution
    /// and "drop 'Y'" for a deletion, so the wording to highlight is whatever is
    /// quoted after one of those leads. "instead of" is checked first: a message
    /// can contain both, and the substitution target is the more specific one.
    private static let offendingTextLeads = ["instead of", "drop", "avoid", "cut"]

    private static func offendingText(in message: String) -> String? {
        for lead in offendingTextLeads {
            guard let marker = message.range(of: lead, options: .caseInsensitive) else { continue }
            if let phrase = firstQuotedPhrase(in: message[marker.upperBound...]) {
                return phrase
            }
        }
        return nil
    }

    /// Straight and curly quotes both appear in model output. An apostrophe
    /// inside a word ("don't") must not be mistaken for a closing quote, so a
    /// closer only counts when it isn't followed by another letter.
    private static func firstQuotedPhrase(in text: Substring) -> String? {
        let closersByOpener: [Character: Set<Character>] = [
            "'": ["'", "\u{2019}"],
            "\"": ["\"", "\u{201D}"],
            "\u{2018}": ["\u{2019}"],
            "\u{201C}": ["\u{201D}"],
        ]
        guard let openIndex = text.firstIndex(where: { closersByOpener[$0] != nil }),
              let closers = closersByOpener[text[openIndex]] else { return nil }

        var index = text.index(after: openIndex)
        while index < text.endIndex {
            if closers.contains(text[index]) {
                let next = text.index(after: index)
                let followedByLetter = next < text.endIndex && text[next].isLetter
                if !followedByLetter {
                    let phrase = String(text[text.index(after: openIndex)..<index])
                    return phrase.isEmpty ? nil : phrase
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
