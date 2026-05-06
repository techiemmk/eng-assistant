import Foundation
import AVFoundation
import Core

/// `AudioPlayback` via `AVAudioPlayer`. Accepts any `AVAudioPlayer`-readable
/// format (WAV, AIFF, MP3, AAC, ...). Returns when playback finishes; capped
/// at a hard timeout to avoid hanging indefinitely if the buffer is malformed.
public final class AVAudioPlaybackImpl: AudioPlayback, @unchecked Sendable {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 60) {
        self.timeout = timeout
    }

    public func play(_ audio: SynthesizedAudio) async throws {
        guard !audio.data.isEmpty else { return }
        let player = try AVAudioPlayer(data: audio.data)
        player.prepareToPlay()
        guard player.play() else {
            throw AVAudioPlaybackError.playbackFailed
        }
        let startedAt = Date()
        while player.isPlaying {
            if Date().timeIntervalSince(startedAt) > timeout {
                player.stop()
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)  // 50 ms
        }
    }
}

public enum AVAudioPlaybackError: Error, Equatable, Sendable {
    case playbackFailed
}
