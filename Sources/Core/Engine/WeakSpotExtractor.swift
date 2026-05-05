import Foundation

public struct WeakSpotCandidate: Equatable, Sendable {
    public let pattern: String
    public let category: WeakSpotCategory

    public init(pattern: String, category: WeakSpotCategory) {
        self.pattern = pattern
        self.category = category
    }
}

public struct WeakSpotExtractor: Sendable {
    private let llm: LLMProvider
    private let options: LLMOptions

    public init(llm: LLMProvider, options: LLMOptions) {
        self.llm = llm
        self.options = options
    }

    public func extract(fromUserTranscript transcript: String) async throws -> [WeakSpotCandidate] {
        guard !transcript.isEmpty else { return [] }
        let system = ChatMessage(role: .system, content: """
            You analyze an English-learner's spoken transcript and identify recurring
            (not one-off) mistakes worth coaching. Reply with ONLY a JSON object:
            {"patterns": [{"pattern": "<short phrase>", "category": "<grammar|vocab|filler|fluency>"}, ...]}
            Each pattern is a 1-line description (e.g. "uses 'more better' instead of 'better'").
            If no recurring patterns stand out, return {"patterns": []}.
            No prose, no markdown — just JSON.
            """)
        let user = ChatMessage(role: .user, content: transcript)
        let stream = try await llm.respond(messages: [system, user], options: options)
        var collected = ""
        for try await chunk in stream {
            collected += chunk
        }
        return parse(collected)
    }

    private func parse(_ raw: String) -> [WeakSpotCandidate] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["patterns"] as? [[String: Any]]
        else {
            return []
        }
        return arr.compactMap { entry in
            guard let pattern = entry["pattern"] as? String, !pattern.isEmpty else { return nil }
            let categoryStr = (entry["category"] as? String) ?? "grammar"
            let category = WeakSpotCategory(rawValue: categoryStr) ?? .grammar
            return WeakSpotCandidate(pattern: pattern, category: category)
        }
    }
}
