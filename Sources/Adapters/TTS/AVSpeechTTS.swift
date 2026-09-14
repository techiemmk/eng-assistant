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
    private let delivery: Delivery

    /// How the utterance is spoken, as distinct from *which* voice speaks it.
    ///
    /// Only the two knobs here actually reach the audio. The app synthesises to
    /// a buffer with `write(_:bufferCallback:)` and plays that buffer back
    /// later, so `preUtteranceDelay` and `postUtteranceDelay` — which schedule
    /// silence around *live* speech — are measurably absent from what gets
    /// written, and are deliberately not exposed. Measured: a 1.0s
    /// `postUtteranceDelay` produced a byte-identical buffer.
    ///
    /// This tuning does *not* substitute for a better voice. On a Mac with only
    /// Apple's stock voices installed it is polish on a fundamentally robotic
    /// timbre — see `SystemVoiceCatalog.hasOnlyStandardVoices`.
    public struct Delivery: Sendable {
        /// `AVSpeechUtterance.rate`. **Bucketed, not continuous:** measured on
        /// macOS 26, 0.46 and 0.47 produce output byte-identical to the 0.5
        /// default, while 0.45 and below cross into the next bucket and slow
        /// speech by about 10%. So the default below is 0.9× rather than a
        /// gentler-looking multiplier that would quietly do nothing.
        public var rate: Float
        /// `AVSpeechUtterance.pitchMultiplier`. Does change the written audio —
        /// verified by comparing buffer contents, which a length comparison
        /// cannot detect.
        public var pitchMultiplier: Float

        public init(
            rate: Float = AVSpeechUtteranceDefaultSpeechRate * 0.9,
            pitchMultiplier: Float = 1.0
        ) {
            self.rate = rate
            self.pitchMultiplier = pitchMultiplier
        }

        /// AVFoundation's own defaults, for comparison in tests.
        public static let avFoundationDefaults = Delivery(
            rate: AVSpeechUtteranceDefaultSpeechRate,
            pitchMultiplier: 1.0
        )

        /// The slowest setting that is still natural, for learners who need more
        /// time to catch the words.
        public static let deliberate = Delivery(
            rate: AVSpeechUtteranceDefaultSpeechRate * 0.8
        )
    }

    public init(timeout: TimeInterval = 30, delivery: Delivery = Delivery()) {
        self.timeout = timeout
        self.delivery = delivery
    }

    public func synthesize(text: String, voice: Voice) async throws -> SynthesizedAudio {
        guard !text.isEmpty else {
            return SynthesizedAudio(data: Data(), sampleRate: 0)
        }
        let utterance = AVSpeechUtterance(string: text)
        // A voice id that isn't installed — a saved choice whose voice the user
        // has since removed — leaves `voice` nil, which AVFoundation resolves to
        // the system default. That's the right fallback, so it isn't an error.
        if let v = AVSpeechSynthesisVoice(identifier: voice.id) {
            utterance.voice = v
        }
        utterance.rate = delivery.rate
        utterance.pitchMultiplier = delivery.pitchMultiplier
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
