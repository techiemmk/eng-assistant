import Testing
import Foundation
@testable import Persistence

@Suite struct StorageLayoutTests {
    @Test func rootContainsAppNameSegment() {
        let layout = StorageLayout(appName: "EngAssistantTest")
        let root = layout.rootDirectory
        #expect(root.path.contains("EngAssistantTest"), "root: \(root.path)")
        #expect(root.path.contains("Application Support"), "root: \(root.path)")
    }

    @Test func knownSubpaths() {
        let layout = StorageLayout(appName: "EngAssistantTest")
        #expect(layout.databaseFile.lastPathComponent == "eng-assistant.sqlite")
        #expect(layout.audioDirectory.lastPathComponent == "audio")
        #expect(layout.transcriptsDirectory.lastPathComponent == "transcripts")
        #expect(layout.modelsDirectory.lastPathComponent == "models")
        #expect(layout.logsDirectory.lastPathComponent == "logs")
    }

    @Test func ensureDirectoriesCreatesThem() throws {
        let unique = "EngAssistantTest-\(UUID().uuidString)"
        let layout = StorageLayout(appName: unique)
        try layout.ensureDirectories()
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: layout.rootDirectory.path))
        #expect(fm.fileExists(atPath: layout.audioDirectory.path))
        #expect(fm.fileExists(atPath: layout.transcriptsDirectory.path))
        #expect(fm.fileExists(atPath: layout.modelsDirectory.path))
        #expect(fm.fileExists(atPath: layout.logsDirectory.path))
        // cleanup
        try? fm.removeItem(at: layout.rootDirectory)
    }
}
