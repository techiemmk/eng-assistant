import Foundation

public protocol AudioFilePersisting: Sendable {
    /// Writes `audio` bytes to disk for the given session/turn. Returns a
    /// path *relative* to the storage root. The Turn's `audioPath` column
    /// stores the relative path so the DB stays portable across machines.
    func write(audio: Data, sessionId: UUID, turnIndex: Int, speaker: Speaker) throws -> String

    /// Removes every clip stored for a session. Succeeds when there was
    /// nothing to remove — deleting a session with no audio isn't a failure.
    func deleteAll(forSession sessionId: UUID) throws
}
