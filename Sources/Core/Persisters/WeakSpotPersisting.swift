import Foundation

public protocol WeakSpotPersisting: Sendable {
    func listActiveByFrequency(limit: Int) throws -> [WeakSpot]
    func create(_ weakSpot: WeakSpot) throws
    func findByPattern(_ pattern: String) throws -> WeakSpot?
    func incrementOccurrence(id: UUID, lastSeen: Date, addExampleTurnId: UUID?) throws
}
