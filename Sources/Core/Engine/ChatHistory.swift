import Foundation

public struct ChatHistory: Sendable {
    public let systemPrompt: String
    public let maxCharacterBudget: Int
    private var turns: [ChatMessage] = []   // user/assistant only; system is separate

    public init(systemPrompt: String, maxCharacterBudget: Int) {
        self.systemPrompt = systemPrompt
        self.maxCharacterBudget = maxCharacterBudget
    }

    public mutating func append(role: ChatRole, content: String) {
        precondition(role != .system, "Only user/assistant turns may be appended")
        turns.append(ChatMessage(role: role, content: content))
        truncateIfNeeded()
    }

    public func messages() -> [ChatMessage] {
        [ChatMessage(role: .system, content: systemPrompt)] + turns
    }

    private var turnsCharCount: Int {
        turns.reduce(0) { $0 + $1.content.count }
    }

    private mutating func truncateIfNeeded() {
        while turnsCharCount > maxCharacterBudget && !turns.isEmpty {
            turns.removeFirst()
            if let next = turns.first, next.role == .assistant {
                turns.removeFirst()
            }
        }
    }
}
