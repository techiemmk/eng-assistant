import Testing
import Foundation
import Persistence
@testable import EngAssistantApp

@Suite struct AudioRetentionSweeperTests {
    @Test func deletesFilesOlderThanRetentionWindow() throws {
        let unique = "EngAssistantTest-\(UUID().uuidString)"
        let layout = StorageLayout(appName: unique)
        try layout.ensureDirectories()
        defer { try? FileManager.default.removeItem(at: layout.rootDirectory) }

        let sessionDir = layout.audioDirectory.appendingPathComponent("session-1", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let oldFile = sessionDir.appendingPathComponent("user-turn-000.wav")
        let newFile = sessionDir.appendingPathComponent("user-turn-001.wav")
        try Data([0]).write(to: oldFile)
        try Data([0]).write(to: newFile)
        // Backdate the old file by 100 days.
        let backDate = Date().addingTimeInterval(-100 * 86400)
        try FileManager.default.setAttributes([.modificationDate: backDate], ofItemAtPath: oldFile.path)

        let sweeper = AudioRetentionSweeper(layout: layout, retentionDays: 30)
        let removed = try sweeper.sweep()
        #expect(removed == 1)
        #expect(!FileManager.default.fileExists(atPath: oldFile.path))
        #expect(FileManager.default.fileExists(atPath: newFile.path))
    }

    @Test func zeroDaysSkipsSweep() throws {
        let unique = "EngAssistantTest-\(UUID().uuidString)"
        let layout = StorageLayout(appName: unique)
        try layout.ensureDirectories()
        defer { try? FileManager.default.removeItem(at: layout.rootDirectory) }

        let sessionDir = layout.audioDirectory.appendingPathComponent("session-1", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let file = sessionDir.appendingPathComponent("user-turn-000.wav")
        try Data([0]).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-100 * 86400)],
            ofItemAtPath: file.path
        )

        let sweeper = AudioRetentionSweeper(layout: layout, retentionDays: 0)
        let removed = try sweeper.sweep()
        #expect(removed == 0)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
