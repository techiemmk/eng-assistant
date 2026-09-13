import Foundation
import AVFoundation

public struct HealthCheck: Sendable {
    /// Probe closure used to test whether the Ollama server is reachable.
    /// Production uses a GET to `/api/tags` via URLSession (any HTTP response
    /// counts — even 4xx/5xx — because the goal is to confirm the server is
    /// up, not that the API call succeeded). Tests substitute their own.
    public typealias ReachabilityProbe = @Sendable (URL) async -> Bool

    /// Probe that returns the raw body of a GET, so the model list can be read
    /// rather than just pinged. `nil` means the request didn't complete.
    public typealias BodyProbe = @Sendable (URL) async -> Data?

    private let probe: ReachabilityProbe
    private let bodyProbe: BodyProbe

    public init(
        probe: @escaping ReachabilityProbe = HealthCheck.defaultProbe,
        bodyProbe: @escaping BodyProbe = HealthCheck.defaultBodyProbe
    ) {
        self.probe = probe
        self.bodyProbe = bodyProbe
    }

    /// Returns true if the Ollama server responds at `baseURL`. Uses a short
    /// timeout (3s) so the wizard doesn't hang.
    public func ollamaReachable(baseURL: URL) async -> Bool {
        let url = baseURL.appendingPathComponent("api").appendingPathComponent("tags")
        return await probe(url)
    }

    /// Names of the models Ollama can run locally, or `nil` if the list couldn't
    /// be read. Hosted ("cloud") entries are filtered out: they appear in
    /// `/api/tags` but answering with one needs an Ollama subscription, so
    /// treating them as installed is how a green setup check turns into a 404
    /// (or 402) on the first conversation turn.
    public func localModels(baseURL: URL) async -> [String]? {
        let url = baseURL.appendingPathComponent("api").appendingPathComponent("tags")
        guard let data = await bodyProbe(url) else { return nil }
        return Self.parseLocalModelNames(data)
    }

    /// Splits `/api/tags` into (isInstalled, allLocalNames). A model counts as
    /// installed on an exact name match, or when the caller left the tag off
    /// (`qwen2.5` matching `qwen2.5:latest`) — which is how `ollama run` works.
    public func modelStatus(baseURL: URL, model: String) async -> (installed: Bool, available: [String])? {
        guard let models = await localModels(baseURL: baseURL) else { return nil }
        let installed = models.contains(model)
            || (!model.contains(":") && models.contains { $0.hasPrefix("\(model):") })
        return (installed, models)
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

    static func parseLocalModelNames(_ data: Data) -> [String]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else { return nil }

        return models.compactMap { entry -> String? in
            guard let name = entry["name"] as? String else { return nil }
            // Two markers for a hosted model: a `remote_host` on the entry, and
            // the `:cloud` tag Ollama gives them.
            if entry["remote_host"] is String { return nil }
            if name.hasSuffix(":cloud") { return nil }
            return name
        }
    }

    /// Default probe: GET the URL via URLSession with a short timeout. Any
    /// HTTP response (including 4xx/5xx) is treated as "reachable" — the
    /// server answered. Only connection failures count as "not reachable".
    public static let defaultProbe: ReachabilityProbe = { url in
        await defaultBodyProbe(url) != nil
    }

    /// Default body probe: GET the URL and hand back the response body for any
    /// HTTP reply. `nil` only on a transport failure.
    public static let defaultBodyProbe: BodyProbe = { url in
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse) != nil else { return nil }
            return data
        } catch {
            return nil
        }
    }
}
