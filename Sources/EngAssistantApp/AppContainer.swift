import Foundation
import Core
import Persistence
import Adapters

/// Composition root. Builds and owns the long-lived dependencies the app
/// needs: the SQLite database, all repositories, the scenario catalog, and
/// adapter factories. View models receive references via init injection.
public final class AppContainer: @unchecked Sendable {
    public let storageLayout: StorageLayout
    public let database: Database
    public let scenarioCatalog: ScenarioCatalog

    public let sessionRepository: SessionRepository
    public let turnRepository: TurnRepository
    public let scenarioRepository: ScenarioRepository
    public let weakSpotRepository: WeakSpotRepository
    public let metricsRepository: MetricsRepository
    public let settingsRepository: SettingsRepository
    public let debriefRepository: DebriefRepository
    public let audioFileStore: AudioFileStore

    public init(storageLayout: StorageLayout = StorageLayout()) throws {
        self.storageLayout = storageLayout
        try storageLayout.ensureDirectories()
        self.database = try Database.onDisk(at: storageLayout.databaseFile)
        self.scenarioCatalog = try ScenarioCatalog.loadBuiltIn()
        self.sessionRepository = SessionRepository(database: database)
        self.turnRepository = TurnRepository(database: database)
        self.scenarioRepository = ScenarioRepository(database: database)
        self.weakSpotRepository = WeakSpotRepository(database: database)
        self.metricsRepository = MetricsRepository(database: database)
        self.settingsRepository = SettingsRepository(database: database)
        self.debriefRepository = DebriefRepository(database: database)
        self.audioFileStore = AudioFileStore(layout: storageLayout)
    }

    /// In-memory database for tests. Audio is still written to the real
    /// filesystem (under a unique test-specific app-support folder) so paths
    /// can be inspected; tests should clean up by removing that folder.
    public static func inMemoryForTesting() throws -> AppContainer {
        let unique = "EngAssistantTest-\(UUID().uuidString)"
        return try AppContainer(storageLayout: StorageLayout(appName: unique))
    }

    /// Builds an OllamaLLM using URLSession. The model name travels separately,
    /// in `LLMOptions` — see `AppSettingsStore.modelName`.
    public func makeLLMProvider() -> LLMProvider {
        OllamaLLM(httpClient: URLSessionHTTPClient())
    }

    /// Builds the real Whisper adapter when both paths are configured (or were
    /// auto-detected); otherwise a provider that explains what's missing.
    @MainActor
    public func makeSTTProvider(settings: AppSettingsStore) -> STTProvider {
        guard settings.isSTTConfigured else { return UnconfiguredSTTProvider() }
        return WhisperLocalSTT(
            runner: ForegroundProcessRunner(),
            executablePath: settings.sttExecutablePath,
            modelPath: settings.sttModelPath
        )
    }

    /// Builds an AVSpeechTTS fallback. Once Piper is configured, this can route
    /// to PiperTTS instead.
    public func makeTTSProvider() -> TTSProvider {
        AVSpeechTTS()
    }

    /// Builds a real mic capture. Will throw at start time if the host doesn't
    /// have microphone permission.
    public func makeAudioCapture() -> AudioCapture {
        AVAudioCaptureImpl()
    }

    public func makeAudioPlayback() -> AudioPlayback {
        AVAudioPlaybackImpl()
    }

    /// The app's saved settings, hydrated by `AppState.bootstrap()`.
    @MainActor
    public func makeSettingsStore() -> AppSettingsStore {
        AppSettingsStore(persister: settingsRepository)
    }

    /// The user's most frequent unresolved weak spots, for coach mode to target.
    /// A failed read must not block a session, so it degrades to "no targets"
    /// rather than throwing — coach mode still corrects what it notices.
    public func activeWeakSpots(limit: Int = AppContainer.coachWeakSpotLimit) -> [WeakSpot] {
        do {
            return try weakSpotRepository.listActiveByFrequency(limit: limit)
        } catch {
            FileHandle.standardError.write(Data("[AppContainer] weak-spot read failed: \(error)\n".utf8))
            return []
        }
    }

    /// Kept small on purpose: these go into every prompt of the session, and a
    /// long list dilutes the instruction rather than sharpening it.
    public static let coachWeakSpotLimit = 5
}
