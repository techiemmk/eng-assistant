import Foundation

public struct StorageLayout: Sendable {
    public let appName: String

    public init(appName: String = "EngAssistant") {
        self.appName = appName
    }

    public var rootDirectory: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent(appName, isDirectory: true)
    }

    public var databaseFile: URL {
        rootDirectory.appendingPathComponent("eng-assistant.sqlite")
    }

    public var audioDirectory: URL {
        rootDirectory.appendingPathComponent("audio", isDirectory: true)
    }

    public var transcriptsDirectory: URL {
        rootDirectory.appendingPathComponent("transcripts", isDirectory: true)
    }

    public var modelsDirectory: URL {
        rootDirectory.appendingPathComponent("models", isDirectory: true)
    }

    public var logsDirectory: URL {
        rootDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    public func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [rootDirectory, audioDirectory, transcriptsDirectory, modelsDirectory, logsDirectory] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
