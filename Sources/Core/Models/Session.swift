import Foundation

public enum SessionMode: String, Codable, Equatable, Sendable, CaseIterable {
    case flow
    case coach
}

public enum SessionStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case active     // started but not ended
    case ended      // user ended cleanly
    case abandoned  // detected on next launch as orphaned and dismissed
}

public struct Session: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let scenarioId: String
    public let startedAt: Date
    public var endedAt: Date?
    public let mode: SessionMode
    public var status: SessionStatus
    public var summary: String?
    public let personaSnapshot: String

    public init(
        id: UUID,
        scenarioId: String,
        startedAt: Date,
        endedAt: Date?,
        mode: SessionMode,
        status: SessionStatus,
        summary: String?,
        personaSnapshot: String
    ) {
        self.id = id
        self.scenarioId = scenarioId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.mode = mode
        self.status = status
        self.summary = summary
        self.personaSnapshot = personaSnapshot
    }
}
