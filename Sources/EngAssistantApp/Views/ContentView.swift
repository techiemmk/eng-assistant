import SwiftUI
import Core
import Persistence
import Adapters

enum AppPane: Hashable {
    case practice
    case session(scenarioId: String, mode: SessionMode)
    case debrief(sessionId: UUID)
    case history
    case settings
}

public struct ContentView: View {
    let container: AppContainer
    @State private var selection: AppPane = .practice

    public init(container: AppContainer) {
        self.container = container
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Practice", systemImage: "mic.fill").tag(AppPane.practice)
                Label("Sessions", systemImage: "clock").tag(AppPane.history)
                Label("Settings", systemImage: "gear").tag(AppPane.settings)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            switch selection {
            case .practice:
                PracticeView(viewModel: PracticeViewModel(catalog: container.scenarioCatalog)) { scenario, mode in
                    selection = .session(scenarioId: scenario.id, mode: mode)
                }
            case .session(let scenarioId, let mode):
                if let scenario = container.scenarioCatalog.scenario(id: scenarioId) {
                    let vm = LiveSessionViewModel(
                        scenario: scenario,
                        mode: mode,
                        llm: container.makeLLMProvider(),
                        stt: ConsoleSTTProvider(),
                        tts: container.makeTTSProvider(),
                        audioCapture: container.makeAudioCapture(),
                        audioPlayback: container.makeAudioPlayback(),
                        sessionPersister: container.sessionRepository,
                        turnPersister: container.turnRepository,
                        audioFilePersister: container.audioFileStore
                    )
                    LiveSessionView(viewModel: vm) { sessionId in
                        selection = .debrief(sessionId: sessionId)
                    }
                    .task { try? await vm.start() }
                } else {
                    Text("Scenario not found")
                }
            case .debrief(let sessionId):
                let analyzer = SessionAnalyzer(
                    grammarJudge: GrammarJudge(llm: container.makeLLMProvider(), options: LLMOptions(modelName: "qwen2.5:7b-instruct")),
                    weakSpotExtractor: WeakSpotExtractor(llm: container.makeLLMProvider(), options: LLMOptions(modelName: "qwen2.5:7b-instruct")),
                    weakSpotMerger: WeakSpotMerger(persister: container.weakSpotRepository),
                    sessionPersister: container.sessionRepository,
                    turnPersister: container.turnRepository,
                    scenarioCatalog: container.scenarioCatalog
                )
                DebriefView(viewModel: DebriefViewModel(analyzer: analyzer, sessionId: sessionId))
            case .history:
                SessionsHistoryView(viewModel: SessionsHistoryViewModel(persister: container.sessionRepository)) { id in
                    selection = .debrief(sessionId: id)
                }
            case .settings:
                SettingsView(viewModel: SettingsViewModel(persister: container.settingsRepository))
            }
        }
        .navigationTitle("EngAssistant")
    }
}

/// Plan 6 ships without a real STT provider wired into the app because real
/// Whisper integration depends on the user installing whisper-cli and choosing
/// a model file. For v1, this dummy STT returns a placeholder transcript.
/// Real STT lands in a Plan 7 polish step.
private struct ConsoleSTTProvider: STTProvider {
    func transcribe(audio: Data) async throws -> Transcript {
        Transcript(text: "[transcription pending whisper.cpp setup]", confidence: 0)
    }
}
