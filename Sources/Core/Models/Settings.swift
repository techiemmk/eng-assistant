import Foundation

public enum AppSettingKey: String, CaseIterable, Sendable {
    case defaultMode = "default_mode"
    case audioRetentionDays = "audio_retention_days"
    case vadSensitivity = "vad_sensitivity"
    case llmModelName = "llm_model_name"
    case ttsVoiceName = "tts_voice_name"
    case sttModelName = "stt_model_name"
    case sttExecutablePath = "stt_executable_path"
    case sttModelPath = "stt_model_path"
    case appearance = "appearance"
    case didCompleteOnboarding = "did_complete_onboarding"
}

/// Which colour scheme the app renders in. Deliberately just the two: the app
/// always picks one rather than inheriting the Mac's setting, so what you see
/// doesn't change under you when the system flips at sunset.
public enum AppearancePreference: String, Codable, Equatable, Sendable, CaseIterable {
    case light
    case dark

    public var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var iconName: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

/// Fallback values used when a setting has never been written. Kept in one
/// place so the LLM model name isn't duplicated across the composition root,
/// the view models, and the smoke CLI.
public enum AppDefaults {
    public static let llmModelName = "qwen2.5:7b-instruct"
    public static let audioRetentionDays = 30
    public static let defaultMode: SessionMode = .flow
    public static let appearance: AppearancePreference = .light
}
