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
            lines.append("Conversation style: stay in character, but if the user makes a clear English mistake, briefly insert a structured correction marker like [[coach: try 'I'd rather' instead of 'I would more like']] right before continuing your reply. Markers are removed before being spoken aloud, so the user only hears your in-character reply.")
            if !activeWeakSpots.isEmpty {
                lines.append("")
                lines.append("Watch especially for these recurring user mistakes:")
                for ws in activeWeakSpots {
                    lines.append("  - \(ws.pattern) (\(ws.category.rawValue))")
                }
            }
        }

        lines.append("")
        lines.append("Difficulty: \(scenario.difficulty)")

        return lines.joined(separator: "\n")
    }
}
