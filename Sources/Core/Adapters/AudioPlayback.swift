import Foundation

public protocol AudioPlayback: Sendable {
    func play(_ audio: SynthesizedAudio) async throws
}
