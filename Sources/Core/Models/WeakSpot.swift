import Foundation

public enum WeakSpotCategory: String, Codable, Equatable, Sendable, CaseIterable {
    case grammar
    case vocab
    case filler
    case fluency
}

public enum WeakSpotStatus: String, Codable, Equatable, Sendable {
    case active
    case resolved
}

public struct WeakSpot: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var pattern: String
    public var category: WeakSpotCategory
    public var firstSeen: Date
    public var lastSeen: Date
    public var occurrenceCount: Int
    public var status: WeakSpotStatus
    public var exampleTurnIds: [UUID]

    public init(
        id: UUID,
        pattern: String,
        category: WeakSpotCategory,
        firstSeen: Date,
        lastSeen: Date,
        occurrenceCount: Int,
        status: WeakSpotStatus,
        exampleTurnIds: [UUID]
    ) {
        self.id = id
        self.pattern = pattern
        self.category = category
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.occurrenceCount = occurrenceCount
        self.status = status
        self.exampleTurnIds = exampleTurnIds
    }
}
