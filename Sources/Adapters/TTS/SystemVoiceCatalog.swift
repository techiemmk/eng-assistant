import Foundation
import AVFoundation
import Core

/// How natural a system voice sounds. Apple ships the lowest tier and makes the
/// better ones an optional download, so a stock Mac has only `standard` voices
/// — which is the single biggest reason the app sounds robotic out of the box.
public enum VoiceQuality: Int, Comparable, Sendable {
    case standard = 1
    case enhanced = 2
    case premium = 3

    public static func < (lhs: VoiceQuality, rhs: VoiceQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .standard: return "Standard"
        case .enhanced: return "Enhanced"
        case .premium: return "Premium"
        }
    }

    /// Whether this tier is worth offering as an upgrade path in the UI.
    public var isHighQuality: Bool { self >= .enhanced }
}

public struct InstalledVoice: Identifiable, Equatable, Sendable {
    /// The `AVSpeechSynthesisVoice` identifier, which is what gets persisted.
    public let id: String
    public let name: String
    /// BCP-47, e.g. `en-GB`.
    public let language: String
    public let quality: VoiceQuality

    public init(id: String, name: String, language: String, quality: VoiceQuality) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
    }

    /// What the engine needs — `Core.Voice` carries only the identifier.
    public var voice: Voice {
        Voice(id: id, displayName: name)
    }

    /// e.g. "Daniel — en-GB · Standard", for a picker row.
    public var pickerLabel: String {
        "\(name) — \(language) · \(quality.label)"
    }
}

/// The speech voices installed on this Mac, for the Settings picker.
public enum SystemVoiceCatalog {
    /// Apple's legacy novelty voices — Zarvox, Boing, Bad News, Bells, Bubbles
    /// and friends — are registered as speech voices and would otherwise fill
    /// the picker with jokes. They all live under this identifier prefix.
    private static let noveltyPrefix = "com.apple.speech.synthesis.voice."

    /// English voices worth offering, best quality first, then by name.
    ///
    /// Sorted best-first on purpose: the whole point of the picker is to move
    /// the user off the low-quality default, so the good ones have to be the
    /// ones they see without scrolling.
    public static func englishVoices() -> [InstalledVoice] {
        voices(matchingLanguagePrefix: "en")
    }

    static func voices(matchingLanguagePrefix prefix: String) -> [InstalledVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .filter { !$0.identifier.hasPrefix(noveltyPrefix) }
            .map {
                InstalledVoice(
                    id: $0.identifier,
                    name: $0.name,
                    language: $0.language,
                    quality: quality(of: $0.quality)
                )
            }
            .sorted {
                $0.quality != $1.quality
                    ? $0.quality > $1.quality
                    : ($0.name, $0.language) < ($1.name, $1.language)
            }
    }

    /// True when the Mac has nothing better than the stock low-quality voices,
    /// which is worth telling the user because the fix is a free download and
    /// no amount of code will substitute for it.
    public static func hasOnlyStandardVoices() -> Bool {
        let voices = englishVoices()
        return !voices.isEmpty && voices.allSatisfy { !$0.quality.isHighQuality }
    }

    /// The voice the system would use if the app expressed no preference —
    /// the fallback, and what shipped before there was a picker.
    public static func systemDefault(language: String = "en-US") -> InstalledVoice? {
        guard let voice = AVSpeechSynthesisVoice(language: language) else { return nil }
        return InstalledVoice(
            id: voice.identifier,
            name: voice.name,
            language: voice.language,
            quality: quality(of: voice.quality)
        )
    }

    private static func quality(of raw: AVSpeechSynthesisVoiceQuality) -> VoiceQuality {
        switch raw {
        case .premium: return .premium
        case .enhanced: return .enhanced
        default: return .standard
        }
    }
}
