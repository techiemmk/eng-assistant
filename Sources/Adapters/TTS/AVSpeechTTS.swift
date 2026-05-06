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
    private var collected = Data()
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
                    let bytes = Data(bytes: channelData, count: count * MemoryLayout<Float>.size)
                    self.collected.append(bytes)
                }
                self.lock.unlock()
            }
        }
    }

    func snapshot() -> SynthesizedAudio {
        lock.lock()
        let result = SynthesizedAudio(data: collected, sampleRate: sampleRate)
        lock.unlock()
        return result
    }

    private func finishOnce() {
        lock.lock()
        let c = continuation
        continuation = nil
        let payload = SynthesizedAudio(data: collected, sampleRate: sampleRate)
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
