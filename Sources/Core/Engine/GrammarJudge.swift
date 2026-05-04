import Foundation

public struct GrammarJudge: Sendable {
    private let llm: LLMProvider
    private let options: LLMOptions

    public init(llm: LLMProvider, options: LLMOptions) {
        self.llm = llm
        self.options = options
    }

    /// Returns the number of clear grammatical errors the LLM identifies in `text`.
    /// Returns 0 if the LLM response cannot be parsed as the expected JSON shape.
    public func countIssues(in text: String) async throws -> Int {
        let system = ChatMessage(role: .system, content: """
            You are a strict grammar judge. The user will give you one English utterance.
            Reply with ONLY a JSON object of the form {"grammarIssueCount": N} where N
            is the number of clear, unambiguous grammatical errors (subject-verb
            agreement, tense, article, preposition, etc.). Do not count stylistic
            choices or filler words. No prose, no explanation, no markdown — just JSON.
            """)
        let user = ChatMessage(role: .user, content: text)
        let stream = try await llm.respond(messages: [system, user], options: options)
        var collected = ""
        for try await chunk in stream {
            collected += chunk
        }
        return parseCount(from: collected)
    }

    private func parseCount(from raw: String) -> Int {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let n = obj["grammarIssueCount"] as? Int,
              n >= 0
        else {
            return 0
        }
        return n
    }
}
