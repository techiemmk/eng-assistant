import Foundation
import Core

public actor FakeAudioCapture: AudioCapture {
    private var scriptedClips: [Data]
    public private(set) var startCount: Int = 0
    public private(set) var stopCount: Int = 0

    public init(scriptedClips: [Data]) {
        self.scriptedClips = scriptedClips
    }

    public init(scriptedClipByteCounts: [Int]) {
        self.scriptedClips = scriptedClipByteCounts.map { Data(repeating: 0, count: $0) }
    }

    public func startRecording() async throws {
        startCount += 1
    }

    public func stopRecording() async throws -> Data {
        stopCount += 1
        guard !scriptedClips.isEmpty else {
            throw FakeAudioCaptureError.scriptExhausted
        }
        return scriptedClips.removeFirst()
    }
}

public enum FakeAudioCaptureError: Error, Equatable {
    case scriptExhausted
}
