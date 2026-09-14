import Foundation

/// Stores a finished debrief so it is computed once, not on every visit.
///
/// Re-analysing was not merely slow: `SessionAnalyzer` merges weak spots as a
/// side effect, so re-opening an old debrief incremented every one of its
/// patterns again. Occurrence counts drifted upward just from reading, and
/// coach mode targets the most frequent patterns — so browsing history quietly
/// steered the coaching.
public protocol DebriefPersisting: Sendable {
    func find(sessionId: UUID) throws -> Debrief?
    func save(_ debrief: Debrief) throws
    func delete(sessionId: UUID) throws
}
