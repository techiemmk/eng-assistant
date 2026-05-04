import Foundation

public protocol WeakSpotPersisting: Sendable {
    func listActiveByFrequency(limit: Int) throws -> [WeakSpot]
}
