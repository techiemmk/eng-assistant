import Foundation
import Core

public actor FakeAudioCapture: AudioCapture {
    private var scriptedClips: [Data]
    /// Number of `hasEndpointed()` calls to answer `false` before reporting an
    /// endpoint. `nil` means never endpoint, matching a device without VAD.
    private let endpointAfterPolls: Int?
    public private(set) var startCount: Int = 0
    public private(set) var stopCount: Int = 0
    public private(set) var endpointPollCount: Int = 0

    public init(scriptedClips: [Data], endpointAfterPolls: Int? = nil) {
        self.scriptedClips = scriptedClips
        self.endpointAfterPolls = endpointAfterPolls
    }

    public init(scriptedClipByteCounts: [Int], endpointAfterPolls: Int? = nil) {
        self.scriptedClips = scriptedClipByteCounts.map { Data(repeating: 0, count: $0) }
        self.endpointAfterPolls = endpointAfterPolls
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

    public func hasEndpointed() async -> Bool {
        endpointPollCount += 1
        guard let threshold = endpointAfterPolls else { return false }
        return endpointPollCount >= threshold
    }
}

public enum FakeAudioCaptureError: Error, Equatable {
    case scriptExhausted
}
