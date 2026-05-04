import Foundation

public protocol TurnPersisting: Sendable {
    func append(_ turn: Turn) throws
    func list(forSession sessionId: UUID) throws -> [Turn]
    func markIncomplete(id: UUID) throws
    func updateMetricsJson(turnId: UUID, json: String) throws
}
