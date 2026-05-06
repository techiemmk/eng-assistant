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
    @Published public private(set) var lastError: String? = nil

    public let scenario: Scenario
    public let mode: SessionMode

    private let engine: SessionEngine
    private let sessionPersister: SessionPersisting
    private let turnPersister: TurnPersisting

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
        modelName: String = "qwen2.5:7b-instruct"
    ) {
        self.scenario = scenario
        self.mode = mode
        self.sessionPersister = sessionPersister
        self.turnPersister = turnPersister
        self.engine = SessionEngine(
            scenario: scenario,
            mode: mode,
            activeWeakSpots: [],
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

    public func start() async throws {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await engine.start()
            transcript = [DisplayTurn(speaker: .ai, text: scenario.openingLine)]
            isActive = true
            lastError = nil
        } catch {
            lastError = "Could not start session: \(error)"
            throw error
        }
    }

    public func runUserTurn() async throws {
        guard isActive else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let corrections = try await engine.runUserTurn()
            // Reload from the persister to get the actual persisted text.
            if let session = try await engine.sessionForTesting() {
                let allTurns = try turnPersister.list(forSession: session.id)
                transcript = allTurns.map { turn in
                    DisplayTurn(
                        speaker: turn.speaker,
                        text: turn.text,
                        corrections: turn.speaker == .ai ? corrections : []
                    )
                }
            }
            lastError = nil
        } catch {
            lastError = "Turn failed: \(error)"
            throw error
        }
    }

    @discardableResult
    public func end() async throws -> UUID {
        let session = try await engine.sessionForTesting()
        let id = session?.id ?? UUID()
        try await engine.end(summary: "Practiced '\(scenario.title)' for \(transcript.count) turns.")
        isActive = false
        return id
    }
}
