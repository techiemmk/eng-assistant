import Foundation

public enum AppSettingKey: String, CaseIterable, Sendable {
    case defaultMode = "default_mode"
    case audioRetentionDays = "audio_retention_days"
    case vadSensitivity = "vad_sensitivity"
    case llmModelName = "llm_model_name"
    case ttsVoiceName = "tts_voice_name"
    case sttModelName = "stt_model_name"
    case didCompleteOnboarding = "did_complete_onboarding"
}
