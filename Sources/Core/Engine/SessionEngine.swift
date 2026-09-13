import Foundation

public actor SessionEngine {
    public let scenario: Scenario
    public let mode: SessionMode
    public let activeWeakSpots: [WeakSpot]
    public let voice: Voice
    public let llmOptions: LLMOptions

    private let llm: LLMProvider
    private let stt: STTProvider
    private let tts: TTSProvider
    private let audioCapture: AudioCapture
    private let audioPlayback: AudioPlayback
    private let sessionPersister: SessionPersisting
    private let turnPersister: TurnPersisting
    private let audioFilePersister: AudioFilePersisting?

    /// Active-session state. `nil` before `start()` and after no session has been
    /// initialized; non-`nil` once `start()` succeeds. Bundling sessionId, history,
    /// and turn index together means a single guard establishes "session in flight"
    /// and the body never has to force-unwrap individual fields.
    private struct ActiveState {
        var sessionId: UUID
        var history: ChatHistory
        var nextTurnIndex: Int
    }
    private var state: ActiveState?

    /// True between `beginUserSpeech()` and `finishUserSpeech()`.
    private var isCapturing: Bool = false

    public static let defaultHistoryBudget = 12_000  // characters; ~3000 tokens at ~4 chars/token

    /// A 16-bit mono WAV with no samples is exactly 44 bytes of header. Anything
    /// at or below this is silence-only, so there is nothing to transcribe and we
    /// fail fast rather than sending an empty clip to the STT provider.
    public static let minimumAudioBytes = 64

    public init(
        scenario: Scenario,
        mode: SessionMode,
        activeWeakSpots: [WeakSpot],
        llm: LLMProvider,
        stt: STTProvider,
        tts: TTSProvider,
        audioCapture: AudioCapture,
        audioPlayback: AudioPlayback,
        sessionPersister: SessionPersisting,
        turnPersister: TurnPersisting,
        voice: Voice,
        llmOptions: LLMOptions,
        audioFilePersister: AudioFilePersisting? = nil
    ) {
        self.scenario = scenario
        self.mode = mode
        self.activeWeakSpots = activeWeakSpots
        self.llm = llm
        self.stt = stt
        self.tts = tts
        self.audioCapture = audioCapture
        self.audioPlayback = audioPlayback
        self.sessionPersister = sessionPersister
        self.turnPersister = turnPersister
        self.voice = voice
        self.llmOptions = llmOptions
        self.audioFilePersister = audioFilePersister
    }

    public func start() async throws {
        let id = UUID()
        let now = Date()
        let session = Session(
            id: id,
            scenarioId: scenario.id,
            startedAt: now,
            endedAt: nil,
            mode: mode,
            status: .active,
            summary: nil,
            personaSnapshot: scenario.persona
        )
        try sessionPersister.create(session)

        let systemPrompt = PersonaBuilder.build(
            scenario: scenario,
            mode: mode,
            activeWeakSpots: activeWeakSpots
        )
        state = ActiveState(
            sessionId: id,
            history: ChatHistory(systemPrompt: systemPrompt, maxCharacterBudget: Self.defaultHistoryBudget),
            nextTurnIndex: 0
        )

        try await speakAndPersistOpeningLine(text: scenario.openingLine)
    }

    /// Opens the microphone and returns immediately. The caller decides when the
    /// turn is over — either by polling `captureHasEndpointed()` (VAD auto-stop)
    /// or on user action — and then calls `finishUserSpeech()`.
    public func beginUserSpeech() async throws {
        guard state != nil else { throw SessionEngineError.notStarted }
        guard !isCapturing else { throw SessionEngineError.alreadyCapturing }
        try await audioCapture.startRecording()
        isCapturing = true
    }

    /// True once the capture device's VAD has seen speech followed by sustained
    /// silence. Returns false when not capturing.
    public func captureHasEndpointed() async -> Bool {
        guard isCapturing else { return false }
        return await audioCapture.hasEndpointed()
    }

    public func isCapturingSpeech() -> Bool {
        isCapturing
    }

    /// Stops recording and discards the clip without running a turn. Used when a
    /// session ends while the mic is still open.
    public func cancelUserSpeech() async {
        guard isCapturing else { return }
        isCapturing = false
        _ = try? await audioCapture.stopRecording()
    }

    /// Runs one full turn from start to finish, opening and closing the mic
    /// itself. Convenience for non-interactive callers (tests, the smoke CLI);
    /// the GUI uses `beginUserSpeech()` / `finishUserSpeech()` so the user
    /// controls how long the mic stays open.
    @discardableResult
    public func runUserTurn() async throws -> [Correction] {
        try await beginUserSpeech()
        return try await finishUserSpeech()
    }

    /// Closes the mic and runs the rest of the turn: transcribe, prompt the LLM,
    /// speak and persist the reply. Atomicity contract: if the LLM (or any step
    /// after the user turn is persisted) throws, the user turn is marked
    /// incomplete and the in-memory `ChatHistory` is NOT updated, so the next
    /// turn doesn't resend a half-broken history to the model.
    @discardableResult
    public func finishUserSpeech() async throws -> [Correction] {
        guard var current = state else { throw SessionEngineError.notStarted }
        guard isCapturing else { throw SessionEngineError.notCapturing }

        let audio: Data
        do {
            audio = try await audioCapture.stopRecording()
            isCapturing = false
        } catch {
            isCapturing = false
            throw error
        }
        guard audio.count > Self.minimumAudioBytes else {
            throw SessionEngineError.noSpeechCaptured
        }
        let userStart = Date()
        let transcript = try await stt.transcribe(audio: audio)
        guard !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Mic was open but the transcriber found no words. Nothing is
            // persisted, so the user can simply talk again.
            throw SessionEngineError.noSpeechCaptured
        }

        let userAudioPath: String?
        do {
            userAudioPath = try audioFilePersister?.write(
                audio: audio,
                sessionId: current.sessionId,
                turnIndex: current.nextTurnIndex,
                speaker: .user
            )
        } catch {
            FileHandle.standardError.write(Data("[SessionEngine] audio persist failed (turn \(current.nextTurnIndex), speaker user): \(error)\n".utf8))
            userAudioPath = nil
        }

        let userTurnId = UUID()
        let userTurn = Turn(
            id: userTurnId,
            sessionId: current.sessionId,
            turnIndex: current.nextTurnIndex,
            speaker: .user,
            text: transcript.text,
            audioPath: userAudioPath,
            startedAt: userStart,
            durationMs: 0,
            metricsJson: nil,
            isComplete: true
        )
        try turnPersister.append(userTurn)
        current.nextTurnIndex += 1
        state = current

        // Build the prompt history WITHOUT mutating `state.history` yet — we only
        // commit to history if the LLM call succeeds end-to-end.
        var pendingHistory = current.history
        pendingHistory.append(role: .user, content: transcript.text)

        let aiStart = Date()
        let fullReply: String
        do {
            let stream = try await llm.respond(messages: pendingHistory.messages(), options: llmOptions)
            var collected = ""
            for try await chunk in stream {
                collected += chunk
            }
            fullReply = collected
        } catch {
            // LLM failed — preserve the user turn as incomplete so the UI can show
            // "reply failed — retry?" without losing what the user said. History
            // stays unchanged so a retry doesn't double-send the user message.
            try? turnPersister.markIncomplete(id: userTurnId)
            throw error
        }

        let parsed = CoachMarkerParser.parse(fullReply)
        pendingHistory.append(role: .assistant, content: fullReply)

        try await speakAndPersistAIReply(
            spokenText: parsed.spokenText,
            originalText: fullReply,
            startedAt: aiStart
        )

        // Both turns succeeded — commit history.
        if var committed = state {
            committed.history = pendingHistory
            state = committed
        }

        return parsed.corrections
    }

    public func end(summary: String?) async throws {
        guard let current = state else { throw SessionEngineError.notStarted }
        await cancelUserSpeech()
        try sessionPersister.finalize(id: current.sessionId, endedAt: Date(), summary: summary)
    }

    // Test helpers
    public func sessionForTesting() throws -> Session? {
        guard let current = state else { return nil }
        return try sessionPersister.find(id: current.sessionId)
    }

    public func llmForTesting() -> LLMProvider {
        llm
    }

    // MARK: - private

    private func speakAndPersistOpeningLine(text: String) async throws {
        guard var current = state else { throw SessionEngineError.notStarted }
        let synthStart = Date()
        let audio = try await tts.synthesize(text: text, voice: voice)
        let playStart = Date()
        try await audioPlayback.play(audio)
        let elapsedPlayback = Int(Date().timeIntervalSince(playStart) * 1000)

        let audioPath: String?
        do {
            audioPath = try audioFilePersister?.write(
                audio: audio.data,
                sessionId: current.sessionId,
                turnIndex: current.nextTurnIndex,
                speaker: .ai
            )
        } catch {
            FileHandle.standardError.write(Data("[SessionEngine] audio persist failed (turn \(current.nextTurnIndex), speaker ai): \(error)\n".utf8))
            audioPath = nil
        }

        let turn = Turn(
            id: UUID(),
            sessionId: current.sessionId,
            turnIndex: current.nextTurnIndex,
            speaker: .ai,
            text: text,
            audioPath: audioPath,
            startedAt: synthStart,
            durationMs: elapsedPlayback,
            metricsJson: nil,
            isComplete: true
        )
        try turnPersister.append(turn)
        current.nextTurnIndex += 1
        state = current
        // Opening line is NOT injected into history — the LLM didn't author it.
    }

    private func speakAndPersistAIReply(spokenText: String, originalText: String, startedAt: Date) async throws {
        guard var current = state else { throw SessionEngineError.notStarted }
        let audio = try await tts.synthesize(text: spokenText, voice: voice)
        let playStart = Date()
        try await audioPlayback.play(audio)
        let elapsedPlayback = Int(Date().timeIntervalSince(playStart) * 1000)

        let audioPath: String?
        do {
            audioPath = try audioFilePersister?.write(
                audio: audio.data,
                sessionId: current.sessionId,
                turnIndex: current.nextTurnIndex,
                speaker: .ai
            )
        } catch {
            FileHandle.standardError.write(Data("[SessionEngine] audio persist failed (turn \(current.nextTurnIndex), speaker ai): \(error)\n".utf8))
            audioPath = nil
        }

        let turn = Turn(
            id: UUID(),
            sessionId: current.sessionId,
            turnIndex: current.nextTurnIndex,
            speaker: .ai,
            text: originalText,
            audioPath: audioPath,
            startedAt: startedAt,
            durationMs: elapsedPlayback,
            metricsJson: nil,
            isComplete: true
        )
        try turnPersister.append(turn)
        current.nextTurnIndex += 1
        state = current
    }
}

public enum SessionEngineError: Error, Equatable {
    case notStarted
    /// `beginUserSpeech()` called while the mic was already open.
    case alreadyCapturing
    /// `finishUserSpeech()` called without a matching `beginUserSpeech()`.
    case notCapturing
    /// The clip held no audio, or the transcriber found no words in it.
    case noSpeechCaptured
}
