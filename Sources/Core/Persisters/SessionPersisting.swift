import Foundation

public protocol SessionPersisting: Sendable {
    func create(_ session: Session) throws
    func find(id: UUID) throws -> Session?
    func finalize(id: UUID, endedAt: Date, summary: String?) throws
    func listActive() throws -> [Session]
}
