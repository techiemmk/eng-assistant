import Foundation
import Persistence

public struct AudioRetentionSweeper {
    private let layout: StorageLayout
    private let retentionDays: Int

    public init(layout: StorageLayout, retentionDays: Int) {
        self.layout = layout
        self.retentionDays = retentionDays
    }

    /// Walks the audio directory; deletes files older than retentionDays.
    /// Returns the count of files removed. Setting retentionDays <= 0 disables
    /// sweeping entirely (audio kept forever).
    @discardableResult
    public func sweep() throws -> Int {
        guard retentionDays > 0 else { return 0 }
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        let fm = FileManager.default
        guard fm.fileExists(atPath: layout.audioDirectory.path) else { return 0 }
        let enumerator = fm.enumerator(
            at: layout.audioDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var removed = 0
        while let url = enumerator?.nextObject() as? URL {
            let resources = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard resources.isRegularFile == true,
                  let mtime = resources.contentModificationDate,
                  mtime < cutoff
            else { continue }
            do {
                try fm.removeItem(at: url)
                removed += 1
            } catch {
                FileHandle.standardError.write(Data("[AudioRetentionSweeper] failed to remove \(url.lastPathComponent): \(error)\n".utf8))
            }
        }
        return removed
    }
}
