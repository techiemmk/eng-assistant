import Foundation
import Core
import Adapters

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var modelName: String = AppDefaults.llmModelName
    @Published public var defaultMode: SessionMode = AppDefaults.defaultMode
    @Published public var audioRetentionDays: Int = AppDefaults.audioRetentionDays
    @Published public var sttExecutablePath: String = ""
    @Published public var sttModelPath: String = ""
    @Published public var appearance: AppearancePreference = AppDefaults.appearance
    /// Empty string means "system default".
    @Published public var ttsVoiceId: String = ""

    /// Installed speech voices, best quality first. Novelty voices are excluded.
    @Published public private(set) var availableVoices: [InstalledVoice] = []
    @Published public private(set) var isPreviewingVoice: Bool = false

    /// A short-lived confirmation such as "Saved." It clears itself after
    /// `noticeDuration`; it used to sit there until the screen was rebuilt,
    /// which meant navigating away and back was the only way to dismiss it.
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
    /// Injected so tests don't depend on which voices this Mac happens to have.
    /// How long a transient confirmation stays on screen before clearing
    /// itself. Injectable so tests don't sit through it, matching
    /// `AppState.launchHold` and `LiveSessionViewModel.endpointPollInterval`.
    private let noticeDuration: Duration
    /// Clears the current notice when it expires. Held so a second save can
    /// cancel the first one's timer — otherwise an older timer would clear the
    /// newer message early.
    private var noticeExpiry: Task<Void, Never>?
    private let voiceCatalog: @Sendable () -> [InstalledVoice]
    /// Speaks a sample so the user can hear a voice before committing to it.
    private let previewSpeaker: @Sendable (Voice) async -> Void
    /// The live settings the rest of the app reads. Kept in sync on save so a
    /// changed model name takes effect without a relaunch.
    private let store: AppSettingsStore?
    private let locator: STTLocator

    public init(
        persister: SettingsPersisting,
        store: AppSettingsStore? = nil,
        locator: STTLocator = STTLocator(),
        healthCheck: HealthCheck = HealthCheck(),
        ollamaBaseURL: URL = URL(string: "http://localhost:11434")!,
        noticeDuration: Duration = SettingsViewModel.defaultNoticeDuration,
        voiceCatalog: @escaping @Sendable () -> [InstalledVoice] = { SystemVoiceCatalog.englishVoices() },
        previewSpeaker: @escaping @Sendable (Voice) async -> Void = SettingsViewModel.speakSample
    ) {
        self.persister = persister
        self.store = store
        self.locator = locator
        self.healthCheck = healthCheck
        self.ollamaBaseURL = ollamaBaseURL
        self.noticeDuration = noticeDuration
        self.voiceCatalog = voiceCatalog
        self.previewSpeaker = previewSpeaker

        // Seed from the live store when there is one. `load()` is async, so
        // without this a freshly-built view model shows defaults for a beat —
        // and if it is built *instead of* being loaded, it shows them forever.
        // That was the visible bug: saving rebuilt this object, and the screen
        // fell back to "System default" and an empty model list.
        if let store {
            modelName = store.modelName
            defaultMode = store.defaultMode
            audioRetentionDays = store.audioRetentionDays
            sttExecutablePath = store.sttExecutablePath
            sttModelPath = store.sttModelPath
            appearance = store.appearance
            ttsVoiceId = store.ttsVoiceId
        }
    }

    /// The rows to offer. A saved voice that is no longer installed still
    /// appears, so opening Settings after deleting a voice doesn't silently
    /// reassign the choice — same reasoning as the model picker.
    public var selectableVoices: [InstalledVoice] {
        guard !ttsVoiceId.isEmpty,
              !availableVoices.contains(where: { $0.id == ttsVoiceId })
        else { return availableVoices }
        return availableVoices + [
            InstalledVoice(id: ttsVoiceId, name: "\(ttsVoiceId) (not installed)",
                           language: "—", quality: .standard)
        ]
    }

    /// True when nothing better than Apple's stock voices is installed. Worth
    /// surfacing: no code change improves the timbre as much as downloading one
    /// of Apple's Enhanced or Premium voices, which is free.
    public var shouldSuggestBetterVoices: Bool {
        !availableVoices.isEmpty && availableVoices.allSatisfy { !$0.quality.isHighQuality }
    }

    public func refreshAvailableVoices() {
        availableVoices = voiceCatalog()
    }

    /// Speaks a short sample in the currently selected voice.
    public func previewVoice() async {
        guard !isPreviewingVoice else { return }
        isPreviewingVoice = true
        defer { isPreviewingVoice = false }
        let selected = availableVoices.first { $0.id == ttsVoiceId }
        await previewSpeaker(selected?.voice ?? Voice(id: ttsVoiceId, displayName: "Selected"))
    }

    /// Production preview: synthesise a line and play it. A fixed sample rather
    /// than arbitrary text so voices are compared on the same words.
    @Sendable
    public static func speakSample(_ voice: Voice) async {
        let tts = AVSpeechTTS()
        let playback = AVAudioPlaybackImpl()
        do {
            let audio = try await tts.synthesize(
                text: "Good morning. What did you finish yesterday, and what are you picking up today?",
                voice: voice
            )
            try await playback.play(audio)
        } catch {
            FileHandle.standardError.write(Data("[SettingsViewModel] voice preview failed: \(error)\n".utf8))
        }
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
            ttsVoiceId = (try persister.get(.ttsVoiceName)) ?? ""
            lastError = nil
        } catch {
            lastError = "Load failed: \(error)"
            throw error
        }
        await refreshAvailableModels()
        refreshAvailableVoices()
    }

    public func save() async throws {
        do {
            try persister.set(.llmModelName, value: modelName)
            try persister.set(.defaultMode, value: defaultMode.rawValue)
            try persister.set(.audioRetentionDays, value: String(audioRetentionDays))
            try persister.set(.sttExecutablePath, value: sttExecutablePath)
            try persister.set(.sttModelPath, value: sttModelPath)
            try persister.set(.appearance, value: appearance.rawValue)
            try persister.set(.ttsVoiceName, value: ttsVoiceId)
            store?.apply(
                modelName: modelName,
                defaultMode: defaultMode,
                audioRetentionDays: audioRetentionDays,
                sttExecutablePath: sttExecutablePath,
                sttModelPath: sttModelPath,
                appearance: appearance,
                ttsVoiceId: ttsVoiceId
            )
            showNotice("Saved.")
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

    /// Seconds a confirmation stays up. Long enough to read, short enough not
    /// to look stuck.
    public static let defaultNoticeDuration: Duration = .seconds(3)

    /// Shows a confirmation and schedules its own removal. Errors deliberately
    /// do *not* expire — they're actionable, so they stay until resolved.
    private func showNotice(_ message: String) {
        noticeExpiry?.cancel()
        savedNotice = message
        let duration = noticeDuration
        noticeExpiry = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.savedNotice = nil
        }
    }

    private func clearNotice() {
        noticeExpiry?.cancel()
        noticeExpiry = nil
        savedNotice = nil
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
        if found.isEmpty {
            clearNotice()
        } else {
            showNotice("Found \(found.joined(separator: " and ")) — Save to apply.")
        }
        lastError = found.isEmpty
            ? "Couldn't find whisper-cli. Install it with `brew install whisper-cpp`, "
                + "and put a ggml model in ~/Library/Application Support/EngAssistant/models/."
            : nil
    }
}
