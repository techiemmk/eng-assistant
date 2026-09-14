import Foundation
import Core

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var modelName: String = AppDefaults.llmModelName
    @Published public var defaultMode: SessionMode = AppDefaults.defaultMode
    @Published public var audioRetentionDays: Int = AppDefaults.audioRetentionDays
    @Published public var sttExecutablePath: String = ""
    @Published public var sttModelPath: String = ""
    @Published public var appearance: AppearancePreference = AppDefaults.appearance

    @Published public private(set) var savedNotice: String? = nil
    @Published public private(set) var lastError: String? = nil

    /// Models Ollama can actually run, so the model can be picked rather than
    /// typed. A free-text field made "model not found" a permanent hazard: a
    /// typo, or a model pulled under a slightly different tag, and every
    /// session failed on its first turn.
    @Published public private(set) var availableModels: [String] = []
    @Published public private(set) var isLoadingModels: Bool = false

    private let persister: SettingsPersisting
    private let healthCheck: HealthCheck
    private let ollamaBaseURL: URL
    /// The live settings the rest of the app reads. Kept in sync on save so a
    /// changed model name takes effect without a relaunch.
    private let store: AppSettingsStore?
    private let locator: STTLocator

    public init(
        persister: SettingsPersisting,
        store: AppSettingsStore? = nil,
        locator: STTLocator = STTLocator(),
        healthCheck: HealthCheck = HealthCheck(),
        ollamaBaseURL: URL = URL(string: "http://localhost:11434")!
    ) {
        self.persister = persister
        self.store = store
        self.locator = locator
        self.healthCheck = healthCheck
        self.ollamaBaseURL = ollamaBaseURL
    }

    /// The list to offer in the picker. The saved model is always included even
    /// when Ollama doesn't report it — otherwise opening Settings while Ollama
    /// is down would silently reassign the model to whatever is first.
    public var selectableModels: [String] {
        availableModels.contains(modelName) || modelName.isEmpty
            ? availableModels
            : availableModels + [modelName]
    }

    /// Asks Ollama what it has. Leaves `availableModels` empty when it can't
    /// be reached, which the screen falls back to a text field for.
    public func refreshAvailableModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        availableModels = await healthCheck.localModels(baseURL: ollamaBaseURL) ?? []
    }

    /// True when neither STT path is filled in — the screen shows a hint and an
    /// "auto-detect" button in that state.
    public var isSTTConfigured: Bool {
        !sttExecutablePath.isEmpty && !sttModelPath.isEmpty
    }

    public func load() async throws {
        do {
            if let v = try persister.get(.llmModelName), !v.isEmpty {
                modelName = v
            }
            if let v = try persister.get(.defaultMode), let m = SessionMode(rawValue: v) {
                defaultMode = m
            }
            if let v = try persister.get(.audioRetentionDays), let d = Int(v), d > 0 {
                audioRetentionDays = d
            }
            // Unset STT paths fall back to whatever is on disk, so a Homebrew
            // whisper install shows up pre-filled instead of blank.
            sttExecutablePath = (try persister.get(.sttExecutablePath).flatMap { $0.isEmpty ? nil : $0 })
                ?? locator.findExecutable() ?? ""
            sttModelPath = (try persister.get(.sttModelPath).flatMap { $0.isEmpty ? nil : $0 })
                ?? locator.findModel() ?? ""
            if let v = try persister.get(.appearance), let a = AppearancePreference(rawValue: v) {
                appearance = a
            }
            lastError = nil
        } catch {
            lastError = "Load failed: \(error)"
            throw error
        }
        await refreshAvailableModels()
    }

    public func save() async throws {
        do {
            try persister.set(.llmModelName, value: modelName)
            try persister.set(.defaultMode, value: defaultMode.rawValue)
            try persister.set(.audioRetentionDays, value: String(audioRetentionDays))
            try persister.set(.sttExecutablePath, value: sttExecutablePath)
            try persister.set(.sttModelPath, value: sttModelPath)
            try persister.set(.appearance, value: appearance.rawValue)
            store?.apply(
                modelName: modelName,
                defaultMode: defaultMode,
                audioRetentionDays: audioRetentionDays,
                sttExecutablePath: sttExecutablePath,
                sttModelPath: sttModelPath,
                appearance: appearance
            )
            savedNotice = "Saved."
            lastError = nil
        } catch {
            lastError = "Save failed: \(error)"
            throw error
        }
    }

    /// Applies and persists the theme immediately — no Save needed, because the
    /// user is choosing it by looking at the result.
    public func selectAppearance(_ appearance: AppearancePreference) {
        self.appearance = appearance
        store?.applyAppearance(appearance)
        if store == nil {
            try? persister.set(.appearance, value: appearance.rawValue)
        }
    }

    /// Re-probes the usual Homebrew locations and the app's models directory.
    public func autodetectSTT() {
        var found: [String] = []
        if let exe = locator.findExecutable() {
            sttExecutablePath = exe
            found.append("whisper binary")
        }
        if let model = locator.findModel() {
            sttModelPath = model
            found.append("model file")
        }
        savedNotice = found.isEmpty
            ? nil
            : "Found \(found.joined(separator: " and ")) — Save to apply."
        lastError = found.isEmpty
            ? "Couldn't find whisper-cli. Install it with `brew install whisper-cpp`, "
                + "and put a ggml model in ~/Library/Application Support/EngAssistant/models/."
            : nil
    }
}
