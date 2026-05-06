import Foundation
import AVFoundation

public struct HealthCheck: Sendable {
    /// Probe closure used to test whether the Ollama server is reachable.
    /// Production uses a GET to `/api/tags` via URLSession (any HTTP response
    /// counts — even 4xx/5xx — because the goal is to confirm the server is
    /// up, not that the API call succeeded). Tests substitute their own.
    public typealias ReachabilityProbe = @Sendable (URL) async -> Bool

    private let probe: ReachabilityProbe

    public init(probe: @escaping ReachabilityProbe = HealthCheck.defaultProbe) {
        self.probe = probe
    }

    /// Returns true if the Ollama server responds at `baseURL`. Uses a short
    /// timeout (3s) so the wizard doesn't hang.
    public func ollamaReachable(baseURL: URL) async -> Bool {
        let url = baseURL.appendingPathComponent("api").appendingPathComponent("tags")
        return await probe(url)
    }

    /// Returns the current microphone permission status. macOS reports one of:
    /// authorized, denied, restricted, notDetermined.
    public func microphoneAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// Requests microphone permission from the user. Returns true on grant.
    public func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Default probe: GET the URL via URLSession with a short timeout. Any
    /// HTTP response (including 4xx/5xx) is treated as "reachable" — the
    /// server answered. Only connection failures count as "not reachable".
    public static let defaultProbe: ReachabilityProbe = { url in
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse) != nil
        } catch {
            return false
        }
    }
}
