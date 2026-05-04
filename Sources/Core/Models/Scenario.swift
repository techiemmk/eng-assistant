import Foundation

public enum ScenarioSource: String, Codable, Equatable, Sendable {
    case builtin
    case custom
}

public enum ScenarioDomain: String, Codable, Equatable, Sendable, CaseIterable {
    case work
    case networking
    case social
}

public struct Scenario: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let source: ScenarioSource
    public let title: String
    public let domain: ScenarioDomain
    public let persona: String
    public let openingLine: String
    public let difficulty: Int     // 1..5
    public let tags: [String]
    public let notes: String?

    public init(
        id: String,
        source: ScenarioSource,
        title: String,
        domain: ScenarioDomain,
        persona: String,
        openingLine: String,
        difficulty: Int,
        tags: [String],
        notes: String?
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.domain = domain
        self.persona = persona
        self.openingLine = openingLine
        self.difficulty = difficulty
        self.tags = tags
        self.notes = notes
    }
}
