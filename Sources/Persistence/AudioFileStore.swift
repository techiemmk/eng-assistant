import Foundation
import Core

public struct AudioFileStore: AudioFilePersisting {
    private let layout: StorageLayout

    public init(layout: StorageLayout) {
        self.layout = layout
    }

    public func write(audio: Data, sessionId: UUID, turnIndex: Int, speaker: Speaker) throws -> String {
        let sessionDir = layout.audioDirectory.appendingPathComponent(sessionId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let filename = String(format: "%@-turn-%03d.wav", speaker.rawValue, turnIndex)
        let url = sessionDir.appendingPathComponent(filename)
        try audio.write(to: url, options: .atomic)
        let rootPath = layout.rootDirectory.path + "/"
        let absolute = url.path
        if absolute.hasPrefix(rootPath) {
            return String(absolute.dropFirst(rootPath.count))
        }
        return absolute
    }
}
