import Foundation
import GRDB

public final class Database {
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
