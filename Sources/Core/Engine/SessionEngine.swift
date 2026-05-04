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

    private var sessionId: UUID?
    private var nextTurnIndex: Int = 0
    private var history: ChatHistory?

    public static let defaultHistoryBudget = 12_000  // characters; ~3000 tokens at ~4 chars/token

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
        llmOptions: LLMOptions
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
    }

    /// Creates the session row, sets up the chat history with the system prompt,
    /// speaks and persists the opening line as an AI turn.
    public func start() async throws {
        let id = UUID()
        sessionId = id
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
        history = ChatHistory(systemPrompt: systemPrompt, maxCharacterBudget: Self.defaultHistoryBudget)

        try await speakAndPersistOpeningLine(text: scenario.openingLine)
    }

    /// Runs one full turn: capture user audio, transcribe, persist user turn,
    /// call LLM, parse markers, speak the spoken portion, persist AI turn.
    /// Returns any corrections extracted from the AI's reply.
    @discardableResult
    public func runUserTurn() async throws -> [Correction] {
        guard sessionId != nil, history != nil else {
            throw SessionEngineError.notStarted
        }

        try await audioCapture.startRecording()
        let audio = try await audioCapture.stopRecording()
        let userStart = Date()
        let transcript = try await stt.transcribe(audio: audio)

        try persistUserTurn(text: transcript.text, audioByteCount: audio.count, startedAt: userStart)
        history!.append(role: .user, content: transcript.text)

        let aiStart = Date()
        let stream = try await llm.respond(messages: history!.messages(), options: llmOptions)
        var fullReply = ""
        for try await chunk in stream {
            fullReply += chunk
        }
        let parsed = CoachMarkerParser.parse(fullReply)
        history!.append(role: .assistant, content: fullReply)

        try await speakAndPersistAIReply(
            spokenText: parsed.spokenText,
            originalText: fullReply,
            startedAt: aiStart
        )

        return parsed.corrections
    }

    /// Finalizes the session row.
    public func end(summary: String?) async throws {
        guard let id = sessionId else { throw SessionEngineError.notStarted }
        try sessionPersister.finalize(id: id, endedAt: Date(), summary: summary)
    }

    // Test helpers — visible to tests via direct call.
    public func sessionForTesting() throws -> Session? {
        guard let id = sessionId else { return nil }
        return try sessionPersister.find(id: id)
    }

    public func llmForTesting() -> LLMProvider {
        llm
    }

    // MARK: - private

    private func speakAndPersistOpeningLine(text: String) async throws {
        let start = Date()
        let audio = try await tts.synthesize(text: text, voice: voice)
        try await audioPlayback.play(audio)
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        try persistAITurn(text: text, durationMs: elapsed, startedAt: start)
        // The opening line is spoken directly from scenario.openingLine, not generated
        // by the LLM, so it must NOT be added to ChatHistory as an assistant turn —
        // doing so would mislead the model into thinking it had said something it didn't.
    }

    private func speakAndPersistAIReply(spokenText: String, originalText: String, startedAt: Date) async throws {
        let synthStart = Date()
        let audio = try await tts.synthesize(text: spokenText, voice: voice)
        try await audioPlayback.play(audio)
        let elapsed = Int(Date().timeIntervalSince(synthStart) * 1000)
        try persistAITurn(text: originalText, durationMs: elapsed, startedAt: startedAt)
    }

    private func persistAITurn(text: String, durationMs: Int, startedAt: Date) throws {
        guard let id = sessionId else { throw SessionEngineError.notStarted }
        let turn = Turn(
            id: UUID(),
            sessionId: id,
            turnIndex: nextTurnIndex,
            speaker: .ai,
            text: text,
            audioPath: nil,
            startedAt: startedAt,
            durationMs: durationMs,
            metricsJson: nil,
            isComplete: true
        )
        try turnPersister.append(turn)
        nextTurnIndex += 1
    }

    private func persistUserTurn(text: String, audioByteCount: Int, startedAt: Date) throws {
        guard let id = sessionId else { throw SessionEngineError.notStarted }
        let turn = Turn(
            id: UUID(),
            sessionId: id,
            turnIndex: nextTurnIndex,
            speaker: .user,
            text: text,
            audioPath: nil,    // wiring to disk audio happens in Plan 5
            startedAt: startedAt,
            durationMs: 0,     // user-turn duration arrives in Plan 5
            metricsJson: nil,
            isComplete: true
        )
        try turnPersister.append(turn)
        nextTurnIndex += 1
    }
}

public enum SessionEngineError: Error, Equatable {
    case notStarted
}
