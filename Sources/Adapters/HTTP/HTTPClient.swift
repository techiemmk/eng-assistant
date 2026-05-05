import Foundation

public protocol HTTPClient: Sendable {
    /// Sends a POST request with the given JSON body and headers, and returns an
    /// async stream of response bytes. The stream yields data chunks as they arrive
    /// (typically newline-delimited JSON). Throws on non-2xx status or transport
    /// failure.
    func postJSONStream(
        url: URL,
        body: Data,
        headers: [String: String]
    ) async throws -> AsyncThrowingStream<Data, Error>
}

public enum HTTPClientError: Error, Equatable, Sendable {
    case transport(String)
    case statusCode(Int)
    case invalidResponse
}
