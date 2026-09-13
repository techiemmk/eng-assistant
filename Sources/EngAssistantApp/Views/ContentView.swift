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
    @ObservedObject var settings: AppSettingsStore
    @State private var selection: AppPane = .practice

    public init(container: AppContainer, settings: AppSettingsStore) {
        self.container = container
        self.settings = settings
    }

    public var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: Theme.appIconSymbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.brand)
                    Text(Theme.appName)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

                List(selection: $selection) {
                    Label("Practice", systemImage: "mic.fill").tag(AppPane.practice)
                    Label("Sessions", systemImage: "clock.fill").tag(AppPane.history)
                    Label("Settings", systemImage: "gearshape.fill").tag(AppPane.settings)
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            switch selection {
            case .practice:
                PracticeView(viewModel: PracticeViewModel(
                    catalog: container.scenarioCatalog,
                    mode: settings.defaultMode
                )) { scenario, mode in
                    selection = .session(scenarioId: scenario.id, mode: mode)
                }
            case .session(let scenarioId, let mode):
                if let scenario = container.scenarioCatalog.scenario(id: scenarioId) {
                    let vm = LiveSessionViewModel(
                        scenario: scenario,
                        mode: mode,
                        llm: container.makeLLMProvider(),
                        stt: container.makeSTTProvider(settings: settings),
                        tts: container.makeTTSProvider(),
                        audioCapture: container.makeAudioCapture(),
                        audioPlayback: container.makeAudioPlayback(),
                        sessionPersister: container.sessionRepository,
                        turnPersister: container.turnRepository,
                        audioFilePersister: container.audioFileStore,
                        modelName: settings.modelName,
                        // Only coach mode acts on these; flow mode never
                        // mentions them, so don't pay for the read.
                        activeWeakSpots: mode == .coach ? container.activeWeakSpots() : []
                    )
                    LiveSessionView(viewModel: vm) { sessionId in
                        selection = .debrief(sessionId: sessionId)
                    }
                    .task { try? await vm.start() }
                } else {
                    Text("Scenario not found")
                }
            case .debrief(let sessionId):
                let analysisOptions = LLMOptions(modelName: settings.modelName)
                let analyzer = SessionAnalyzer(
                    grammarJudge: GrammarJudge(llm: container.makeLLMProvider(), options: analysisOptions),
                    weakSpotExtractor: WeakSpotExtractor(llm: container.makeLLMProvider(), options: analysisOptions),
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
                SettingsView(viewModel: SettingsViewModel(persister: container.settingsRepository, store: settings))
            }
        }
        .navigationTitle(Theme.appName)
    }
}
