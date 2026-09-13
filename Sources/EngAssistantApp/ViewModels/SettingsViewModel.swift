import Foundation
import Core

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var modelName: String = AppDefaults.llmModelName
    @Published public var defaultMode: SessionMode = AppDefaults.defaultMode
    @Published public var audioRetentionDays: Int = AppDefaults.audioRetentionDays
    @Published public var sttExecutablePath: String = ""
    @Published public var sttModelPath: String = ""

    @Published public private(set) var savedNotice: String? = nil
    @Published public private(set) var lastError: String? = nil

    private let persister: SettingsPersisting
    /// The live settings the rest of the app reads. Kept in sync on save so a
    /// changed model name takes effect without a relaunch.
    private let store: AppSettingsStore?
    private let locator: STTLocator

    public init(
        persister: SettingsPersisting,
        store: AppSettingsStore? = nil,
        locator: STTLocator = STTLocator()
    ) {
        self.persister = persister
        self.store = store
        self.locator = locator
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
            lastError = nil
        } catch {
            lastError = "Load failed: \(error)"
            throw error
        }
    }

    public func save() async throws {
        do {
            try persister.set(.llmModelName, value: modelName)
            try persister.set(.defaultMode, value: defaultMode.rawValue)
            try persister.set(.audioRetentionDays, value: String(audioRetentionDays))
            try persister.set(.sttExecutablePath, value: sttExecutablePath)
            try persister.set(.sttModelPath, value: sttModelPath)
            store?.apply(
                modelName: modelName,
                defaultMode: defaultMode,
                audioRetentionDays: audioRetentionDays,
                sttExecutablePath: sttExecutablePath,
                sttModelPath: sttModelPath
            )
            savedNotice = "Saved."
            lastError = nil
        } catch {
            lastError = "Save failed: \(error)"
            throw error
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
