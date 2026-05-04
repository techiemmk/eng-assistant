import Foundation

public protocol TurnPersisting: Sendable {
    func append(_ turn: Turn) throws
    func list(forSession sessionId: UUID) throws -> [Turn]
    func markIncomplete(id: UUID) throws
    // NOTE: `updateMetricsJson` is intentionally not part of this protocol yet.
    // Plan 3's MetricsAnalyzer will be the first caller; the protocol is
    // narrowed here to only what SessionEngine actually uses.
}
