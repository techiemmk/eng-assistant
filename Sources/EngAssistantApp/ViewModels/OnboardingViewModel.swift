import Foundation
import AVFoundation
import Core

@MainActor
public final class OnboardingViewModel: ObservableObject {
    public enum CheckStatus: Equatable {
        case unknown
        case running
        case ok
        case failed(String)
    }

    @Published public private(set) var ollamaStatus: CheckStatus = .unknown
    /// Whether the configured model is actually installed. Reachability alone
    /// isn't enough: Ollama answers `/api/tags` happily with no models pulled,
    /// and then 404s the first conversation turn.
    @Published public private(set) var modelStatus: CheckStatus = .unknown
    @Published public private(set) var micStatus: CheckStatus = .unknown
    @Published public private(set) var sttStatus: CheckStatus = .unknown
    @Published public private(set) var allOK: Bool = false

    private let healthCheck: HealthCheck
    private let locator: STTLocator
    private let baseURL: URL
    private var modelName: String

    public init(
        healthCheck: HealthCheck = HealthCheck(),
        locator: STTLocator = STTLocator(),
        baseURL: URL = URL(string: "http://localhost:11434")!,
        modelName: String = AppDefaults.llmModelName
    ) {
        self.healthCheck = healthCheck
        self.locator = locator
        self.baseURL = baseURL
        self.modelName = modelName
    }

    /// Called once settings are loaded, so the model check targets the model the
    /// user actually configured rather than the built-in default.
    public func setModelName(_ name: String) {
        guard !name.isEmpty else { return }
        modelName = name
    }

    public func runChecks() async {
        ollamaStatus = .running
        modelStatus = .running
        let reachable = await healthCheck.ollamaReachable(baseURL: baseURL)
        if reachable {
            ollamaStatus = .ok
            modelStatus = await checkModel()
        } else {
            ollamaStatus = .failed("Ollama isn't running on \(baseURL.absoluteString). Try `ollama serve`.")
            modelStatus = .failed("Can't check models until Ollama is running.")
        }

        micStatus = .running
        let mic = healthCheck.microphoneAuthorizationStatus()
        switch mic {
        case .authorized:
            micStatus = .ok
        case .notDetermined:
            let granted = await healthCheck.requestMicrophone()
            micStatus = granted ? .ok : .failed("Microphone access was not granted.")
        case .denied, .restricted:
            micStatus = .failed("Microphone access denied. Open System Settings > Privacy & Security > Microphone to grant.")
        @unknown default:
            micStatus = .failed("Unknown microphone permission state.")
        }

        sttStatus = checkSTT()

        // The STT check is advisory — the app is usable (if one-sided) without
        // it, and it can be set up later in Settings.
        allOK = ollamaStatus == .ok && modelStatus == .ok && micStatus == .ok
    }

    private func checkModel() async -> CheckStatus {
        guard let status = await healthCheck.modelStatus(baseURL: baseURL, model: modelName) else {
            return .failed("Couldn't read Ollama's model list from \(baseURL.absoluteString).")
        }
        if status.installed { return .ok }
        if status.available.isEmpty {
            return .failed("No local Ollama models installed. Run `ollama pull \(modelName)`.")
        }
        return .failed("'\(modelName)' isn't installed. Run `ollama pull \(modelName)`, or pick one of: "
                       + status.available.joined(separator: ", ") + " in Settings.")
    }

    private func checkSTT() -> CheckStatus {
        let executable = locator.findExecutable()
        let model = locator.findModel()
        switch (executable, model) {
        case (.some, .some):
            return .ok
        case (.none, _):
            return .failed("whisper-cli not found. `brew install whisper-cpp` to enable speech-to-text "
                           + "(you can do this later in Settings).")
        case (.some, .none):
            return .failed("No ggml model found. Put one in ~/Library/Application Support/EngAssistant/models/ "
                           + "(you can do this later in Settings).")
        }
    }
}
