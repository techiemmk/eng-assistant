import Foundation

public enum Speaker: String, Codable, Equatable, Sendable {
    case user
    case ai
}

public struct Turn: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionId: UUID
    public let turnIndex: Int
    public let speaker: Speaker
    public var text: String
    public var audioPath: String?
    public let startedAt: Date
    public var durationMs: Int
    public var metricsJson: String?
    public var isComplete: Bool

    public init(
        id: UUID,
        sessionId: UUID,
        turnIndex: Int,
        speaker: Speaker,
        text: String,
        audioPath: String?,
        startedAt: Date,
        durationMs: Int,
        metricsJson: String?,
        isComplete: Bool
    ) {
        self.id = id
        self.sessionId = sessionId
        self.turnIndex = turnIndex
        self.speaker = speaker
        self.text = text
        self.audioPath = audioPath
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.metricsJson = metricsJson
        self.isComplete = isComplete
    }
}
