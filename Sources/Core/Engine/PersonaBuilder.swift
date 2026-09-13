import Foundation

public enum PersonaBuilder {
    public static func build(
        scenario: Scenario,
        mode: SessionMode,
        activeWeakSpots: [WeakSpot]
    ) -> String {
        var lines: [String] = []
        lines.append("You are roleplaying as: \(scenario.persona)")
        lines.append("")
        lines.append("Goal: hold a natural English conversation with the user. Do not break character.")
        lines.append("")

        switch mode {
        case .flow:
            lines.append("Conversation style: stay completely in character. Do not correct the user's English even if they make mistakes — that feedback happens after the session ends.")
        case .coach:
            lines.append("Conversation style: stay in character, but if the user makes a clear English mistake, insert a correction marker right before continuing your reply. Markers are removed before being spoken aloud, so the user only hears your in-character reply.")
            lines.append("")
            lines.append("Marker format — [[coach:<category>: try '<correct wording>' instead of '<the user's exact wrong wording>']]")
            lines.append("  - <category> is one of: \(WeakSpotCategory.allCases.map(\.rawValue).joined(separator: ", ")).")
            lines.append("  - Always flag clear grammar mistakes (verb tense, subject-verb agreement, articles, prepositions, plurals) with category 'grammar'.")
            lines.append("  - Quote the user's wrong wording verbatim after \"instead of\" so it can be highlighted in the transcript.")
            lines.append("  - When the fix is simply to delete a word (filler, padding), write drop '<the word>' instead — never 'try X instead of X'.")
            lines.append("  - One marker per mistake, at most two per reply. If the user's English was fine, emit no marker.")
            lines.append("")
            lines.append("Example — [[coach:grammar: try 'I finished' instead of 'I have finish']]")
            lines.append("Example — [[coach:filler: drop 'actually']]")

            if !activeWeakSpots.isEmpty {
                lines.append("")
                lines.append("This user keeps making these mistakes. Watch for them especially, and flag them whenever they recur:")
                for ws in activeWeakSpots {
                    lines.append("  - \(ws.pattern) (\(ws.category.rawValue), seen \(ws.occurrenceCount)x)")
                }
            }
        }

        lines.append("")
        lines.append("Difficulty: \(scenario.difficulty)")

        return lines.joined(separator: "\n")
    }
}
