import Foundation

public struct Correction: Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
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
            corrections.append(Correction(message: body.trimmingCharacters(in: .whitespaces)))
            remaining = afterOpen[closeRange.upperBound...]
        }
        spoken += remaining
        return ParsedReply(spokenText: spoken, corrections: corrections)
    }
}
