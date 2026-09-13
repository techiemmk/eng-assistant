import Foundation
import Core

@MainActor
public final class LiveSessionViewModel: ObservableObject {
    public struct DisplayTurn: Identifiable, Equatable {
        public let id = UUID()
        public let speaker: Speaker
        public let text: String
        public var corrections: [Correction] = []
    }

    @Published public private(set) var transcript: [DisplayTurn] = []
    @Published public private(set) var isActive: Bool = false
    @Published public private(set) var isProcessing: Bool = false
    /// True while the mic is open, i.e. between the two taps of push-to-talk.
    @Published public private(set) var isListening: Bool = false
    @Published public private(set) var lastError: String? = nil
    /// True when this screen picked up an existing conversation rather than
    /// opening a new one, so the header can say so.
    @Published public private(set) var isResumed: Bool = false

    public let scenario: Scenario
    public let mode: SessionMode
    /// Recurring mistakes coach mode is told to watch for. Surfaced in the
    /// header so the user can see what's being targeted this session.
    public let activeWeakSpots: [WeakSpot]

    private let engine: SessionEngine
    private let sessionPersister: SessionPersisting
    private let turnPersister: TurnPersisting

    /// How often the VAD flag is polled while recording. 200 ms is well under
    /// the endpointer's 1.5 s silence window, so auto-stop lands promptly
    /// without spinning the actor.
    private let endpointPollInterval: Duration
    private var endpointWatcher: Task<Void, Never>?

    public init(
        scenario: Scenario,
        mode: SessionMode,
        llm: LLMProvider,
        stt: STTProvider,
        tts: TTSProvider,
        audioCapture: AudioCapture,
        audioPlayback: AudioPlayback,
        sessionPersister: SessionPersisting,
        turnPersister: TurnPersisting,
        audioFilePersister: AudioFilePersisting?,
        modelName: String = AppDefaults.llmModelName,
        activeWeakSpots: [WeakSpot] = [],
        endpointPollInterval: Duration = .milliseconds(200)
    ) {
        self.scenario = scenario
        self.mode = mode
        self.activeWeakSpots = activeWeakSpots
        self.sessionPersister = sessionPersister
        self.turnPersister = turnPersister
        self.endpointPollInterval = endpointPollInterval
        self.engine = SessionEngine(
            scenario: scenario,
            mode: mode,
            activeWeakSpots: activeWeakSpots,
            llm: llm,
            stt: stt,
            tts: tts,
            audioCapture: audioCapture,
            audioPlayback: audioPlayback,
            sessionPersister: sessionPersister,
            turnPersister: turnPersister,
            voice: Voice(id: "default", displayName: "Default"),
            llmOptions: LLMOptions(modelName: modelName),
            audioFilePersister: audioFilePersister
        )
    }

    /// Continues an existing conversation: the engine reloads its context from
    /// the stored turns and the transcript shows what was already said, instead
    /// of replaying the scenario's opening line.
    public func resume(sessionId: UUID) async throws {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await engine.resume(sessionId: sessionId)
            let storedTurns = try await engine.storedTurns()
            transcript = storedTurns.map {
                DisplayTurn(speaker: $0.speaker, text: $0.text)
            }
            isActive = true
            isResumed = true
            lastError = nil
        } catch {
            lastError = "Could not continue session: \(FriendlyError.message(for: error))"
            throw error
        }
    }

    public func start() async throws {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await engine.start()
            transcript = [DisplayTurn(speaker: .ai, text: scenario.openingLine)]
            isActive = true
            lastError = nil
        } catch {
            lastError = "Could not start session: \(FriendlyError.message(for: error))"
            throw error
        }
    }

    /// One tap of push-to-talk: opens the mic and leaves it open. Either the
    /// user taps again (`stopListening()`) or the endpointer notices they've
    /// stopped talking and finishes the turn for them.
    public func startListening() async {
        guard isActive, !isListening, !isProcessing else { return }
        do {
            try await engine.beginUserSpeech()
            isListening = true
            lastError = nil
            watchForEndpoint()
        } catch {
            lastError = FriendlyError.message(for: error)
        }
    }

    /// Closes the mic and runs the turn.
    public func stopListening() async {
        guard isListening else { return }
        endpointWatcher?.cancel()
        endpointWatcher = nil
        isListening = false
        isProcessing = true
        defer { isProcessing = false }
        do {
            let corrections = try await engine.finishUserSpeech()
            await refreshTranscript(corrections: corrections)
            lastError = nil
        } catch {
            lastError = FriendlyError.message(for: error)
        }
    }

    public func toggleListening() async {
        if isListening {
            await stopListening()
        } else {
            await startListening()
        }
    }

    /// Runs a whole turn in one call — used by tests and any non-interactive
    /// caller. The GUI goes through `startListening()` / `stopListening()`.
    public func runUserTurn() async throws {
        guard isActive else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let corrections = try await engine.runUserTurn()
            await refreshTranscript(corrections: corrections)
            lastError = nil
        } catch {
            lastError = FriendlyError.message(for: error)
            throw error
        }
    }

    @discardableResult
    public func end() async throws -> UUID {
        endpointWatcher?.cancel()
        endpointWatcher = nil
        isListening = false
        let session = try await engine.sessionForTesting()
        let id = session?.id ?? UUID()
        try await engine.end(summary: "Practiced '\(scenario.title)' for \(transcript.count) turns.")
        isActive = false
        return id
    }

    // MARK: - private

    /// Polls the capture device's endpointer and finishes the turn once the
    /// speaker has gone quiet. Capture devices without VAD never report an
    /// endpoint, so those sessions just wait for the second tap.
    private func watchForEndpoint() {
        endpointWatcher?.cancel()
        let interval = endpointPollInterval
        endpointWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { return }
                guard let self else { return }
                guard await self.engine.captureHasEndpointed() else { continue }
                await self.stopListening()
                return
            }
        }
    }

    /// Reloads the turn list from the persister so the UI shows exactly what was
    /// stored, rather than a second copy assembled in memory.
    private func refreshTranscript(corrections: [Correction]) async {
        guard let session = try? await engine.sessionForTesting(),
              let allTurns = try? turnPersister.list(forSession: session.id) else { return }

        // The AI writes the markers, but they describe what the *user* just
        // said — so they attach to the user turn being corrected (the last one),
        // which is also the text the grammar highlight has to land in.
        let latestUserIndex = allTurns.lastIndex { $0.speaker == .user }
        transcript = allTurns.enumerated().map { offset, turn in
            DisplayTurn(
                speaker: turn.speaker,
                text: turn.text,
                corrections: offset == latestUserIndex ? corrections : []
            )
        }
    }
}
