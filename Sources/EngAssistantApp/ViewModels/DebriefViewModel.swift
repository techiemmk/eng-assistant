import Foundation
import Core

@MainActor
public final class DebriefViewModel: ObservableObject {
    @Published public private(set) var debrief: Debrief?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastError: String? = nil

    private let analyzer: SessionAnalyzing
    public let sessionId: UUID

    public init(analyzer: SessionAnalyzing, sessionId: UUID) {
        self.analyzer = analyzer
        self.sessionId = sessionId
    }

    public func load() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            debrief = try await analyzer.analyze(sessionId: sessionId)
            lastError = nil
        } catch {
            lastError = "Analysis failed: \(error)"
            throw error
        }
    }
}
