import Testing
import Foundation
import AVFoundation
import Core
@testable import Adapters

/// The voice picker is only as good as this list. Novelty voices must not reach
/// it, and the best-quality voices have to sort to the top — the whole point is
/// to move the user off Apple's low-quality default.
@Suite struct SystemVoiceCatalogTests {
    @Test func offersEnglishVoices() {
        let voices = SystemVoiceCatalog.englishVoices()
        #expect(!voices.isEmpty, "no English voices found at all")
        #expect(voices.allSatisfy { $0.language.hasPrefix("en") })
    }

    /// Zarvox, Boing, Bad News, Bells, Bubbles and friends are registered as
    /// speech voices and would otherwise fill the picker with jokes.
    @Test func excludesNoveltyVoices() {
        let voices = SystemVoiceCatalog.englishVoices()
        let names = Set(voices.map(\.name))
        for novelty in ["Zarvox", "Boing", "Bells", "Bubbles", "Bad News", "Trinoids", "Jester"] {
            #expect(!names.contains(novelty), "\(novelty) should not be offered")
        }
        #expect(voices.allSatisfy {
            !$0.id.hasPrefix("com.apple.speech.synthesis.voice.")
        })
    }

    /// The real speech voices must survive the filter — it would be easy to
    /// exclude everything and call the picker "clean".
    @Test func keepsRealSpeechVoices() {
        let ids = SystemVoiceCatalog.englishVoices().map(\.id)
        #expect(ids.contains { $0.hasPrefix("com.apple.voice.") },
                "the modern voice family was filtered out")
    }

    @Test func sortsBestQualityFirst() {
        let voices = SystemVoiceCatalog.englishVoices()
        let qualities = voices.map(\.quality)
        #expect(qualities == qualities.sorted(by: >), "voices aren't ordered best-first")
    }

    @Test func everyVoiceHasAUsableLabelAndIdentifier() {
        for voice in SystemVoiceCatalog.englishVoices() {
            #expect(!voice.id.isEmpty)
            #expect(!voice.name.isEmpty)
            #expect(voice.pickerLabel.contains(voice.name))
            #expect(voice.pickerLabel.contains(voice.quality.label))
            // The identifier is what gets persisted and handed back to
            // AVFoundation, so it has to resolve.
            #expect(AVSpeechSynthesisVoice(identifier: voice.id) != nil,
                    "\(voice.id) doesn't resolve back to a voice")
        }
    }

    @Test func aVoiceConvertsToTheEnginesVoiceType() {
        let voice = SystemVoiceCatalog.englishVoices().first!
        #expect(voice.voice.id == voice.id)
        #expect(voice.voice.displayName == voice.name)
    }

    @Test func systemDefaultIsReported() {
        let fallback = SystemVoiceCatalog.systemDefault()
        #expect(fallback != nil)
        #expect(fallback?.id.isEmpty == false)
    }

    /// Reports honestly whichever way this machine is configured — the point is
    /// that the flag tracks the installed set rather than being hardcoded.
    @Test func highQualityFlagMatchesTheInstalledVoices() {
        let voices = SystemVoiceCatalog.englishVoices()
        let anyHighQuality = voices.contains { $0.quality.isHighQuality }
        #expect(SystemVoiceCatalog.hasOnlyStandardVoices() == !anyHighQuality)
    }

    @Test func qualityTiersOrderAndLabelCorrectly() {
        #expect(VoiceQuality.premium > VoiceQuality.enhanced)
        #expect(VoiceQuality.enhanced > VoiceQuality.standard)
        #expect(VoiceQuality.premium.isHighQuality)
        #expect(VoiceQuality.enhanced.isHighQuality)
        #expect(!VoiceQuality.standard.isHighQuality)
        #expect(VoiceQuality.standard.label == "Standard")
    }
}

private var liveAudioEnabled: Bool {
    ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1"
}

/// These assert what was *measured* about AVFoundation, so a future edit that
/// picks a nicer-looking number can't silently turn the tuning into a no-op.
///
/// Gated like `LiveProvidersTests`: they drive the real speech synthesiser,
/// which crashes the test process when run without a host application.
@Suite(.disabled(if: !liveAudioEnabled, "Set RUN_LIVE_TESTS=1 to enable"))
struct AVSpeechDeliveryTests {
    private static let line = "Good morning. What did you finish yesterday?"

    private static func voice() -> Voice {
        SystemVoiceCatalog.englishVoices().first!.voice
    }

    /// `AVSpeechUtterance.rate` is bucketed: 0.46-0.47 are indistinguishable
    /// from the 0.5 default, so a timid multiplier does nothing at all.
    @Test func theDefaultRateIsLowEnoughToActuallyTakeEffect() async throws {
        let voice = Self.voice()
        let tuned = try await AVSpeechTTS().synthesize(text: Self.line, voice: voice)
        let stock = try await AVSpeechTTS(delivery: .avFoundationDefaults)
            .synthesize(text: Self.line, voice: voice)

        #expect(tuned.data != stock.data, "the rate default is inside AVFoundation's own bucket — it does nothing")
        #expect(tuned.data.count > stock.data.count, "tuned speech should be slower, so longer")
    }

    @Test func slowerRatesProduceLongerAudio() async throws {
        let voice = Self.voice()
        let normal = try await AVSpeechTTS(delivery: .avFoundationDefaults)
            .synthesize(text: Self.line, voice: voice)
        let deliberate = try await AVSpeechTTS(delivery: .deliberate)
            .synthesize(text: Self.line, voice: voice)
        #expect(deliberate.data.count > normal.data.count)
    }

    /// Pitch changes the samples without changing their count, so this has to
    /// compare contents — a length check would wrongly report it as a no-op.
    @Test func pitchChangesTheAudioContent() async throws {
        let voice = Self.voice()
        let flat = try await AVSpeechTTS(delivery: .init(rate: 0.5, pitchMultiplier: 1.0))
            .synthesize(text: Self.line, voice: voice)
        let high = try await AVSpeechTTS(delivery: .init(rate: 0.5, pitchMultiplier: 1.8))
            .synthesize(text: Self.line, voice: voice)
        #expect(flat.data != high.data)
    }

    /// Selecting a voice has to reach the audio. Before the picker existed the
    /// engine was handed `Voice(id: "default")`, which is not a real identifier,
    /// so AVFoundation silently fell back to the system voice every time.
    @Test func differentVoicesProduceDifferentAudio() async throws {
        let voices = SystemVoiceCatalog.englishVoices()
        try #require(voices.count >= 2)
        let tts = AVSpeechTTS()
        let first = try await tts.synthesize(text: Self.line, voice: voices[0].voice)
        let second = try await tts.synthesize(text: Self.line, voice: voices[1].voice)
        #expect(first.data != second.data)
        #expect(first.data.count > 1000, "no real audio was produced")
    }

    @Test func anUnknownVoiceIdFallsBackInsteadOfFailing() async throws {
        let audio = try await AVSpeechTTS()
            .synthesize(text: Self.line, voice: Voice(id: "not.a.real.voice", displayName: "x"))
        #expect(audio.data.count > 1000, "an unknown voice should fall back to the system one")
    }
}
