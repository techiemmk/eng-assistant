import Foundation

public struct WeakSpotMergeResult: Equatable, Sendable {
    public let newlyCreated: [WeakSpot]
    public let recurring: [WeakSpot]
}

public struct WeakSpotMerger: Sendable {
    private let persister: WeakSpotPersisting

    public init(persister: WeakSpotPersisting) {
        self.persister = persister
    }

    /// `sessionUserTurnIds` is used for attaching example turn ids to weak spots —
    /// for v1 we attach the first user turn id of the session as a representative
    /// example. Cleaner per-pattern attachment is a future improvement.
    public func merge(
        candidates: [WeakSpotCandidate],
        sessionUserTurnIds: [UUID],
        now: Date
    ) throws -> WeakSpotMergeResult {
        var newlyCreated: [WeakSpot] = []
        var recurring: [WeakSpot] = []
        let exampleTurnId = sessionUserTurnIds.first

        for candidate in candidates {
            if let existing = try persister.findByPattern(candidate.pattern) {
                try persister.incrementOccurrence(
                    id: existing.id,
                    lastSeen: now,
                    addExampleTurnId: exampleTurnId
                )
                if let after = try persister.findByPattern(candidate.pattern) {
                    recurring.append(after)
                }
            } else {
                let ws = WeakSpot(
                    id: UUID(),
                    pattern: candidate.pattern,
                    category: candidate.category,
                    firstSeen: now,
                    lastSeen: now,
                    occurrenceCount: 1,
                    status: .active,
                    exampleTurnIds: exampleTurnId.map { [$0] } ?? []
                )
                try persister.create(ws)
                newlyCreated.append(ws)
            }
        }
        return WeakSpotMergeResult(newlyCreated: newlyCreated, recurring: recurring)
    }
}
