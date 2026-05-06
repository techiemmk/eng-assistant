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
        self.audioFileStore = AudioFileStore(layout: storageLayout)
    }

    /// In-memory database for tests. Audio is still written to the real
    /// filesystem (under a unique test-specific app-support folder) so paths
    /// can be inspected; tests should clean up by removing that folder.
    public static func inMemoryForTesting() throws -> AppContainer {
        let unique = "EngAssistantTest-\(UUID().uuidString)"
        return try AppContainer(storageLayout: StorageLayout(appName: unique))
    }

    /// Builds an OllamaLLM using URLSession, with the model name from settings
    /// (or a default).
    public func makeLLMProvider() -> LLMProvider {
        OllamaLLM(httpClient: URLSessionHTTPClient())
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
}
