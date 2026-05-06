import Testing
import Foundation
import Core
@testable import Persistence

@Suite struct AudioFileStoreTests {
    @Test func writesUserAudioToDiskAndReturnsRelativePath() throws {
        let unique = "EngAssistantTest-\(UUID().uuidString)"
        let layout = StorageLayout(appName: unique)
        try layout.ensureDirectories()
        defer { try? FileManager.default.removeItem(at: layout.rootDirectory) }

        let store = AudioFileStore(layout: layout)
        let sessionId = UUID()
        let bytes = Data(repeating: 0x42, count: 1024)
        let path = try store.write(audio: bytes, sessionId: sessionId, turnIndex: 3, speaker: .user)
        #expect(path.hasPrefix("audio/"))
        #expect(path.hasSuffix("user-turn-003.wav"))

        let absolute = layout.rootDirectory.appendingPathComponent(path)
        let read = try Data(contentsOf: absolute)
        #expect(read == bytes)
    }

    @Test func writesAITurnToCorrectName() throws {
        let unique = "EngAssistantTest-\(UUID().uuidString)"
        let layout = StorageLayout(appName: unique)
        try layout.ensureDirectories()
        defer { try? FileManager.default.removeItem(at: layout.rootDirectory) }

        let store = AudioFileStore(layout: layout)
        let path = try store.write(
            audio: Data([1, 2, 3]),
            sessionId: UUID(),
            turnIndex: 0,
            speaker: .ai
        )
        #expect(path.hasSuffix("ai-turn-000.wav"))
    }

    @Test func createsSessionDirIfMissing() throws {
        let unique = "EngAssistantTest-\(UUID().uuidString)"
        let layout = StorageLayout(appName: unique)
        try layout.ensureDirectories()
        defer { try? FileManager.default.removeItem(at: layout.rootDirectory) }

        let store = AudioFileStore(layout: layout)
        let sessionId = UUID()
        _ = try store.write(audio: Data([0]), sessionId: sessionId, turnIndex: 0, speaker: .user)
        let sessionDir = layout.audioDirectory.appendingPathComponent(sessionId.uuidString)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: sessionDir.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }
}
