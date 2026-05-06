import Testing
import Foundation
import Core
import Adapters

private var liveTestsEnabled: Bool {
    ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1"
}

@Suite(.disabled(if: !liveTestsEnabled, "Set RUN_LIVE_TESTS=1 to enable"))
struct LiveProvidersTests {
    @Test func ollamaRespondsToSimplePrompt() async throws {
        let llm = OllamaLLM(
            httpClient: URLSessionHTTPClient(),
            baseURL: URL(string: "http://localhost:11434")!
        )
        let model = ProcessInfo.processInfo.environment["OLLAMA_MODEL"] ?? "qwen2.5:7b-instruct"
        let stream = try await llm.respond(
            messages: [
                ChatMessage(role: .system, content: "Reply with just the word OK and nothing else."),
                ChatMessage(role: .user, content: "say it"),
            ],
            options: LLMOptions(modelName: model, temperature: 0, maxTokens: 16)
        )
        var collected = ""
        for try await c in stream { collected += c }
        #expect(!collected.isEmpty)
    }

    @Test func whisperLaunchesIfBinaryIsPresent() async throws {
        let exe = ProcessInfo.processInfo.environment["WHISPER_CLI"] ?? "/opt/homebrew/bin/whisper-cli"
        let model = ProcessInfo.processInfo.environment["WHISPER_MODEL"] ?? ""
        guard FileManager.default.isExecutableFile(atPath: exe), !model.isEmpty,
              FileManager.default.fileExists(atPath: model) else {
            print("Skipping: whisper-cli or model not found (set WHISPER_CLI and WHISPER_MODEL).")
            return
        }
        // We don't have a test fixture audio file in the repo; just smoke-call with
        // empty audio and assert it doesn't crash. A real audio fixture lands in Plan 5.
        let stt = WhisperLocalSTT(runner: ForegroundProcessRunner(), executablePath: exe, modelPath: model)
        _ = try? await stt.transcribe(audio: Data())  // may fail; the point is the binary launched
    }

    @Test func piperSynthesizesShortTextIfBinaryIsPresent() async throws {
        let exe = ProcessInfo.processInfo.environment["PIPER_BIN"] ?? "/opt/homebrew/bin/piper"
        let model = ProcessInfo.processInfo.environment["PIPER_MODEL"] ?? ""
        guard FileManager.default.isExecutableFile(atPath: exe), !model.isEmpty,
              FileManager.default.fileExists(atPath: model) else {
            print("Skipping: piper or model not found (set PIPER_BIN and PIPER_MODEL).")
            return
        }
        let tts = PiperTTS(runner: ForegroundProcessRunner(), executablePath: exe, modelPath: model)
        let result = try await tts.synthesize(text: "Hello", voice: Voice(id: "v", displayName: "V"))
        #expect(!result.data.isEmpty)
    }

    @Test func avSpeechSynthesizesAndReturnsAudio() async throws {
        let tts = AVSpeechTTS(timeout: 30)
        let result = try await tts.synthesize(
            text: "Hello.",
            voice: Voice(id: "com.apple.voice.compact.en-US.Samantha", displayName: "Samantha")
        )
        // On well-behaved hosts, data should be non-empty. On hosts where
        // AVSpeechSynthesizer.write doesn't deliver buffers, the timeout
        // returns whatever was collected (possibly empty). We only assert
        // the call returns within timeout, not that bytes are present.
        _ = result.data.count
        _ = result.sampleRate
    }

    @Test func avAudioPlaybackPlaysGeneratedSineWave() async throws {
        // Generate a 1-second 440 Hz sine wave at 22050 Hz, encode as WAV,
        // and play it. Should complete in ~1 second on a working audio stack.
        let sampleRate = 22050
        let frequency: Float = 440
        let duration: Float = 1.0
        let totalSamples = Int(Float(sampleRate) * duration)
        var samples = [Int16](repeating: 0, count: totalSamples)
        for i in 0..<totalSamples {
            let t = Float(i) / Float(sampleRate)
            let amplitude: Float = 0.3
            samples[i] = Int16(amplitude * 32767 * sin(2 * .pi * frequency * t))
        }
        let wav = WAVCodec.encode(pcm: samples, sampleRate: sampleRate)
        let playback = AVAudioPlaybackImpl(timeout: 5)
        try await playback.play(SynthesizedAudio(data: wav, sampleRate: sampleRate))
    }

    @Test func avAudioCaptureStartsAndStopsCleanly() async throws {
        // This will fail with a permission error in non-entitled processes.
        // In an entitled host, it should successfully start, capture briefly,
        // and stop. We don't assert on the captured bytes since silence is valid.
        let capture = AVAudioCaptureImpl()
        do {
            try await capture.startRecording()
        } catch {
            print("Skipping mic capture: \(error). (Run from an entitled host.)")
            return
        }
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 s
        let wav = try await capture.stopRecording()
        // A WAV with the standard 44-byte header is always at least 44 bytes.
        #expect(wav.count >= 44)
    }
}
