import Foundation
import AVFoundation
import Core

/// `AudioCapture` backed by `AVAudioEngine`. Records from the default input
/// device, applies VAD endpointing, accumulates samples at the configured
/// sample rate (default 16 kHz mono Int16 PCM — what whisper.cpp consumes),
/// and returns WAV-encoded Data on `stopRecording()`.
///
/// **Permission:** `AVAudioEngine.start()` requires the host process to have
/// microphone permission. SPM CLI tools cannot get this; the bundled
/// `.app` from Plan 6 will. Unit tests do not call `startRecording()`.
public final class AVAudioCaptureImpl: AudioCapture, @unchecked Sendable {
    public let sampleRate: Int

    private let engine = AVAudioEngine()
    private var vad: VADEndpointer
    private let lock = NSLock()
    private var buffer: [Int16] = []
    private var endpointed: Bool = false

    public init(sampleRate: Int = 16000, vad: VADEndpointer = VADEndpointer(speechThreshold: 0.05, silenceWindowMs: 1500)) {
        self.sampleRate = sampleRate
        self.vad = vad
    }

    public func startRecording() async throws {
        lock.lock()
        buffer.removeAll(keepingCapacity: true)
        vad.reset()
        endpointed = false
        lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: true
        )!
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] inputBuffer, _ in
            guard let self else { return }
            let frameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * Double(self.sampleRate) / inputFormat.sampleRate + 16)
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }
            var error: NSError?
            converter?.convert(to: output, error: &error) { _, status in
                status.pointee = .haveData
                return inputBuffer
            }
            if error != nil { return }

            var rms: Float = 0
            if let chans = inputBuffer.floatChannelData {
                let n = Int(inputBuffer.frameLength)
                if n > 0 {
                    var sumSq: Float = 0
                    for i in 0..<n { sumSq += chans[0][i] * chans[0][i] }
                    rms = (sumSq / Float(n)).squareRoot()
                }
            }
            let frameDurationMs = Int(Double(inputBuffer.frameLength) / inputFormat.sampleRate * 1000.0)

            self.lock.lock()
            if let int16Data = output.int16ChannelData {
                let frames = Int(output.frameLength)
                for i in 0..<frames {
                    self.buffer.append(int16Data[0][i])
                }
            }
            self.vad.feed(rmsFrame: rms, durationMs: max(frameDurationMs, 1))
            if self.vad.state == .endpointed {
                self.endpointed = true
            }
            self.lock.unlock()
        }

        try engine.start()
    }

    public func stopRecording() async throws -> Data {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        let captured = buffer
        buffer.removeAll(keepingCapacity: false)
        lock.unlock()
        return WAVCodec.encode(pcm: captured, sampleRate: sampleRate)
    }

    /// Returns true if VAD detected end-of-speech during recording. Callers can
    /// poll this between frames to auto-stop, or rely on push-to-talk and
    /// ignore the flag.
    public func isEndpointed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return endpointed
    }
}
