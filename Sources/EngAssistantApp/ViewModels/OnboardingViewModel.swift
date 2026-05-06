import Foundation
import AVFoundation

@MainActor
public final class OnboardingViewModel: ObservableObject {
    public enum CheckStatus: Equatable {
        case unknown
        case running
        case ok
        case failed(String)
    }

    @Published public private(set) var ollamaStatus: CheckStatus = .unknown
    @Published public private(set) var micStatus: CheckStatus = .unknown
    @Published public private(set) var allOK: Bool = false

    private let healthCheck: HealthCheck
    private let baseURL: URL

    public init(healthCheck: HealthCheck = HealthCheck(), baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.healthCheck = healthCheck
        self.baseURL = baseURL
    }

    public func runChecks() async {
        ollamaStatus = .running
        let ollama = await healthCheck.ollamaReachable(baseURL: baseURL)
        ollamaStatus = ollama ? .ok : .failed("Ollama isn't running on \(baseURL.absoluteString). Try `ollama serve`.")

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

        allOK = ollamaStatus == .ok && micStatus == .ok
    }
}
