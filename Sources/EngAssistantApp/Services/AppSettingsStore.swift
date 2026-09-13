import Foundation
import Core

/// The app's *saved* settings, held in one observable place so the composition
/// root and the live-session screen read the same values the Settings screen
/// wrote. Before this existed, `SettingsViewModel` persisted `llm_model_name`
/// and nothing ever read it back — every session used a hardcoded model name.
@MainActor
public final class AppSettingsStore: ObservableObject {
    @Published public private(set) var modelName: String = AppDefaults.llmModelName
    @Published public private(set) var defaultMode: SessionMode = AppDefaults.defaultMode
    @Published public private(set) var audioRetentionDays: Int = AppDefaults.audioRetentionDays

    /// Empty when speech-to-text hasn't been configured or auto-detected.
    @Published public private(set) var sttExecutablePath: String = ""
    @Published public private(set) var sttModelPath: String = ""

    private let persister: SettingsPersisting

    public init(persister: SettingsPersisting) {
        self.persister = persister
    }

    public var isSTTConfigured: Bool {
        !sttExecutablePath.isEmpty && !sttModelPath.isEmpty
    }

    /// Hydrates from the database. Unset keys keep their default; unset STT
    /// paths fall back to auto-detection so a Homebrew whisper install works
    /// without the user filling in anything.
    public func reload(autodetect: STTLocator = STTLocator()) {
        modelName = nonEmpty(.llmModelName) ?? AppDefaults.llmModelName
        defaultMode = (nonEmpty(.defaultMode).flatMap(SessionMode.init(rawValue:))) ?? AppDefaults.defaultMode
        audioRetentionDays = (nonEmpty(.audioRetentionDays).flatMap(Int.init)).flatMap { $0 > 0 ? $0 : nil }
            ?? AppDefaults.audioRetentionDays
        sttExecutablePath = nonEmpty(.sttExecutablePath) ?? autodetect.findExecutable() ?? ""
        sttModelPath = nonEmpty(.sttModelPath) ?? autodetect.findModel() ?? ""
    }

    /// Called by `SettingsViewModel` once a save succeeds, so open screens pick
    /// the new values up without a relaunch.
    public func apply(
        modelName: String,
        defaultMode: SessionMode,
        audioRetentionDays: Int,
        sttExecutablePath: String,
        sttModelPath: String
    ) {
        self.modelName = modelName.isEmpty ? AppDefaults.llmModelName : modelName
        self.defaultMode = defaultMode
        self.audioRetentionDays = audioRetentionDays
        self.sttExecutablePath = sttExecutablePath
        self.sttModelPath = sttModelPath
    }

    private func nonEmpty(_ key: AppSettingKey) -> String? {
        // `try?` flattens the optional the persister already returns.
        guard let value = try? persister.get(key), !value.isEmpty else { return nil }
        return value
    }
}
