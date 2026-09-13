import Foundation

public protocol SessionPersisting: Sendable {
    func create(_ session: Session) throws
    func find(id: UUID) throws -> Session?
    func finalize(id: UUID, endedAt: Date, summary: String?) throws
    /// Puts a finished session back into `.active` and clears its end time, so
    /// a conversation can be picked up where it left off.
    func reactivate(id: UUID) throws
    func listActive() throws -> [Session]
    func listRecent(limit: Int) throws -> [Session]
}
