import Foundation
import AVFoundation
import Adapters

public struct HealthCheck: Sendable {
    private let httpClient: HTTPClient

    public init(httpClient: HTTPClient = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    /// Returns true if the Ollama HTTP endpoint accepts a connection. Any
    /// response (including a 4xx/5xx error body) counts — the test we really
    /// want is "is Ollama running on this port?", not "is the API healthy".
    public func ollamaReachable(baseURL: URL) async -> Bool {
        let url = baseURL.appendingPathComponent("api").appendingPathComponent("tags")
        let body = Data("{}".utf8)
        do {
            let stream = try await httpClient.postJSONStream(url: url, body: body, headers: [:])
            for try await _ in stream {}
            return true
        } catch {
            return false
        }
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
}
