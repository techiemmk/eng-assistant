import Foundation

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func postJSONStream(
        url: URL,
        body: Data,
        headers: [String: String]
    ) async throws -> AsyncThrowingStream<Data, Error> {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPClientError.statusCode(http.statusCode)
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var buffer = Data()
                    for try await byte in bytes {
                        buffer.append(byte)
                        if byte == 0x0A {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
