import Foundation

public enum ScenarioSource: String, Codable, Equatable, Sendable {
    case builtin
    case custom
}

/// The practice areas a scenario can belong to. Every scenario belongs to
/// exactly one, so these partition the catalog and drive the filter chips on
/// the Practice screen.
///
/// This replaced a single broad `work` case, which had become useless as a
/// filter once it held clinical, homeopathic and office scenarios together.
public enum ScenarioDomain: String, Codable, Equatable, Sendable, CaseIterable {
    case homeopathy
    case medical
    case networking
    case social
    case corporate

    /// The order the filter chips appear in. Declared explicitly rather than
    /// leaning on `allCases`, so reordering the enum can't silently reshuffle
    /// the UI — and so a new domain that someone forgets to list here is caught
    /// by `ScenarioDomainTests.displayOrderCoversEveryDomain` instead of just
    /// vanishing from the screen.
    public static let displayOrder: [ScenarioDomain] = [
        .homeopathy, .medical, .networking, .social, .corporate,
    ]

    /// Title-cased for display. Every case happens to capitalise cleanly.
    public var label: String {
        rawValue.capitalized
    }
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
