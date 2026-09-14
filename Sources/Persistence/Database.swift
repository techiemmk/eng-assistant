import Foundation
import GRDB

/// The `Sendable` conformance is checked, not asserted: the only stored
/// property is an immutable `let` of GRDB's `DatabaseQueue`, which is itself
/// `Sendable` (`DatabaseReader: AnyObject, Sendable`, and `DatabaseQueue`
/// conforms to it). Repositories hold a `Database` and conform to `Sendable`
/// persister protocols, so without this they can't be checked either.
public final class Database: Sendable {
    public let queue: DatabaseQueue

    private init(queue: DatabaseQueue) {
        self.queue = queue
    }

    public static func inMemory() throws -> Database {
        let queue = try DatabaseQueue()
        try Migrations.register().migrate(queue)
        return Database(queue: queue)
    }

    public static func onDisk(at url: URL) throws -> Database {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: url.path)
        try Migrations.register().migrate(queue)
        return Database(queue: queue)
    }
}
