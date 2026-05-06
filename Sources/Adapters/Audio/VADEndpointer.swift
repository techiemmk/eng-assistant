import Foundation

public struct VADEndpointer: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case speaking
        case endpointed
    }

    public let speechThreshold: Float
    public let silenceWindowMs: Int

    public private(set) var state: State = .idle
    private var silenceAccumulatedMs: Int = 0

    public init(speechThreshold: Float, silenceWindowMs: Int) {
        self.speechThreshold = speechThreshold
        self.silenceWindowMs = silenceWindowMs
    }

    public mutating func feed(rmsFrame: Float, durationMs: Int) {
        if state == .endpointed { return }
        if rmsFrame >= speechThreshold {
            state = .speaking
            silenceAccumulatedMs = 0
        } else if state == .speaking {
            silenceAccumulatedMs += durationMs
            if silenceAccumulatedMs >= silenceWindowMs {
                state = .endpointed
            }
        }
    }

    public mutating func reset() {
        state = .idle
        silenceAccumulatedMs = 0
    }
}
