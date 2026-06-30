import Foundation
import AVFoundation
import Core

/// `TTSProvider` backed by Apple's `AVSpeechSynthesizer`. Used as a zero-config
/// fallback when Piper isn't installed.
///
/// **macOS quirk:** `AVSpeechSynthesizer.write(_:bufferCallback:)` does not
/// reliably deliver the documented empty-buffer sentinel on every macOS
/// release — on some hosts it never fires, leaving naive callers hung. We use
/// the synthesizer delegate's `didFinish` signal as the primary completion
/// edge and back it up with a per-utterance timeout. Real-audio verification
/// is in `LiveProvidersTests`.
public final class AVSpeechTTS: TTSProvider, @unchecked Sendable {
    /// Maximum wall time per `synthesize` call before returning what's collected.
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 30) {
        self.timeout = timeout
    }

    public func synthesize(text: String, voice: Voice) async throws -> SynthesizedAudio {
        guard !text.isEmpty else {
            return SynthesizedAudio(data: Data(), sampleRate: 0)
        }
        let utterance = AVSpeechUtterance(string: text)
        if let v = AVSpeechSynthesisVoice(identifier: voice.id) {
            utterance.voice = v
        }
        let collector = AVSpeechCollector()
        let synth = AVSpeechSynthesizer()
        synth.delegate = collector
        collector.synth = synth

        return try await withThrowingTaskGroup(of: SynthesizedAudio.self) { group in
            group.addTask {
                await collector.run(utterance: utterance)
            }
            group.addTask { [timeout] in
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return collector.snapshot()
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }
}

private final class AVSpeechCollector: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    /// All mutable state below is guarded by `lock`. Lock is held only briefly
    /// inside accessors — never across `continuation.resume`, to avoid blocking
    /// the synth's internal queue on a continuation hop.
    private let lock = NSLock()
    /// Mono Int16 PCM samples, converted from the synthesizer's Float32 buffers
    /// as they arrive. Stored as Int16 so we can hand them straight to
    /// `WAVCodec.encode` at completion — `AVAudioPlayer(data:)` requires a
    /// recognized container, so returning raw PCM bytes makes playback fail
    /// with kAudioFileUnsupportedFileTypeError ('typ?').
    private var samples: [Int16] = []
    private var sampleRate: Int = 0
    private var continuation: CheckedContinuation<SynthesizedAudio, Never>?
    weak var synth: AVSpeechSynthesizer?

    func run(utterance: AVSpeechUtterance) async -> SynthesizedAudio {
        await withCheckedContinuation { c in
            lock.lock()
            self.continuation = c
            lock.unlock()
            self.synth?.write(utterance) { [weak self] buffer in
                guard let self, let pcm = buffer as? AVAudioPCMBuffer else { return }
                self.lock.lock()
                if self.sampleRate == 0 {
                    self.sampleRate = Int(pcm.format.sampleRate)
                }
                if pcm.frameLength > 0, let channelData = pcm.floatChannelData?.pointee {
                    let count = Int(pcm.frameLength)
                    self.samples.reserveCapacity(self.samples.count + count)
                    for i in 0..<count {
                        let clamped = max(-1.0, min(1.0, channelData[i]))
                        self.samples.append(Int16(clamped * 32767))
                    }
                }
                self.lock.unlock()
            }
        }
    }

    private func makePayloadLocked() -> SynthesizedAudio {
        guard !samples.isEmpty else {
            return SynthesizedAudio(data: Data(), sampleRate: 0)
        }
        let wav = WAVCodec.encode(pcm: samples, sampleRate: sampleRate)
        return SynthesizedAudio(data: wav, sampleRate: sampleRate)
    }

    func snapshot() -> SynthesizedAudio {
        lock.lock()
        let result = makePayloadLocked()
        lock.unlock()
        return result
    }

    private func finishOnce() {
        lock.lock()
        let c = continuation
        continuation = nil
        let payload = makePayloadLocked()
        lock.unlock()
        c?.resume(returning: payload)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishOnce()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishOnce()
    }
}
