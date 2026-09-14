import Foundation
import Core

@MainActor
public final class DebriefViewModel: ObservableObject {
    @Published public private(set) var debrief: Debrief?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastError: String? = nil

    /// Weak spots the user has retired. Held separately from `debrief` because
    /// the debrief is a cached snapshot of the session — resolving a pattern
    /// changes its status now, not what was true at the time.
    @Published public private(set) var resolvedWeakSpotIds: Set<UUID> = []

    /// The turn currently playing back, so only one play button shows as active.
    @Published public private(set) var playingTurnId: UUID? = nil

    private let analyzer: SessionAnalyzing
    private let weakSpotPersister: WeakSpotPersisting?
    private let audioPlayback: AudioPlayback?
    /// Turn `audioPath` is stored relative to the storage root, so the database
    /// stays portable across machines; this is what makes it absolute again.
    private let audioRoot: URL?

    public let sessionId: UUID

    public init(
        analyzer: SessionAnalyzing,
        sessionId: UUID,
        weakSpotPersister: WeakSpotPersisting? = nil,
        audioPlayback: AudioPlayback? = nil,
        audioRoot: URL? = nil
    ) {
        self.analyzer = analyzer
        self.sessionId = sessionId
        self.weakSpotPersister = weakSpotPersister
        self.audioPlayback = audioPlayback
        self.audioRoot = audioRoot
    }

    public func load() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await analyzer.analyze(sessionId: sessionId)
            debrief = loaded
            hydrateResolvedState(from: loaded)
            lastError = nil
        } catch {
            lastError = "Analysis failed: \(FriendlyError.message(for: error))"
            throw error
        }
    }

    // MARK: - weak spots

    public func isResolved(_ weakSpot: WeakSpot) -> Bool {
        resolvedWeakSpotIds.contains(weakSpot.id)
    }

    /// Retires a pattern. Marked locally as well as persisted so the row
    /// updates immediately rather than after a reload.
    public func resolve(_ weakSpot: WeakSpot) {
        guard let weakSpotPersister else { return }
        do {
            try weakSpotPersister.markResolved(id: weakSpot.id)
            resolvedWeakSpotIds.insert(weakSpot.id)
            lastError = nil
        } catch {
            lastError = "Could not resolve that weak spot: \(FriendlyError.message(for: error))"
        }
    }

    /// A cached debrief records the weak spots as they were when the session
    /// was analysed, so anything resolved since would come back looking active.
    /// Re-reading their current status keeps the screen honest.
    private func hydrateResolvedState(from debrief: Debrief) {
        guard let weakSpotPersister else { return }
        let all = debrief.newlyCreatedWeakSpots + debrief.recurringWeakSpots
        resolvedWeakSpotIds = Set(
            all.compactMap { spot in
                guard let current = try? weakSpotPersister.findByPattern(spot.pattern),
                      current.status == .resolved
                else { return nil }
                return spot.id
            }
        )
    }

    // MARK: - audio replay

    /// Whether this turn has a recording on disk to play.
    public func hasAudio(_ turn: Turn) -> Bool {
        audioURL(for: turn) != nil
    }

    /// Plays a turn's recording. Hearing your own answer back is the point of
    /// keeping the .wav files at all — they were written from the first
    /// version and never playable until now.
    public func play(_ turn: Turn) async {
        guard let audioPlayback, let url = audioURL(for: turn) else { return }
        guard playingTurnId == nil else { return }
        playingTurnId = turn.id
        defer { playingTurnId = nil }
        do {
            let data = try Data(contentsOf: url)
            // AVAudioPlayer reads the sample rate from the WAV header itself,
            // so the value here is not consulted.
            try await audioPlayback.play(SynthesizedAudio(data: data, sampleRate: 16000))
            lastError = nil
        } catch {
            lastError = "Couldn't play that clip: \(FriendlyError.message(for: error))"
        }
    }

    private func audioURL(for turn: Turn) -> URL? {
        guard let audioRoot, let path = turn.audioPath, !path.isEmpty else { return nil }
        let url = audioRoot.appendingPathComponent(path)
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return url
    }
}
