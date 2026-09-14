import SwiftUI
import Core
import Persistence
import Adapters

enum AppPane: Hashable {
    case practice
    /// `resuming` carries the session to continue; nil opens a fresh one.
    case session(scenarioId: String, mode: SessionMode, resuming: UUID?)
    case debrief(sessionId: UUID)
    case history
    case settings
}

public struct ContentView: View {
    let container: AppContainer
    @ObservedObject var settings: AppSettingsStore
    /// A session left unfinished by a crash or a quit mid-conversation, offered
    /// once at launch. Passed as a plain value rather than by observing
    /// `AppState`: this view is rebuilt by the `App` body whenever that state
    /// changes, so the value is always current and the view stays ignorant of
    /// the app's root state object.
    let unfinishedSession: Session?
    /// Returns the session to resume and clears the offer.
    let takeUnfinishedSession: () -> Session?
    let discardUnfinishedSession: () -> Void
    @State private var selection: AppPane = .practice

    public init(
        container: AppContainer,
        settings: AppSettingsStore,
        unfinishedSession: Session? = nil,
        takeUnfinishedSession: @escaping () -> Session? = { nil },
        discardUnfinishedSession: @escaping () -> Void = {}
    ) {
        self.container = container
        self.settings = settings
        self.unfinishedSession = unfinishedSession
        self.takeUnfinishedSession = takeUnfinishedSession
        self.discardUnfinishedSession = discardUnfinishedSession
    }

    public var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: Theme.appIconSymbol)
                        .font(Theme.screenIcon)
                        .foregroundStyle(Theme.brand)
                    Text(Theme.appName)
                        .font(Theme.cardTitle)
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
            .navigationSplitViewColumnWidth(min: 230, ideal: 265)
        } detail: {
            switch selection {
            case .practice:
                PracticeView(viewModel: PracticeViewModel(
                    catalog: container.scenarioCatalog,
                    mode: settings.defaultMode
                )) { scenario, mode in
                    selection = .session(scenarioId: scenario.id, mode: mode, resuming: nil)
                }
            case .session(let scenarioId, let mode, let resuming):
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
                    .task {
                        if let resuming {
                            try? await vm.resume(sessionId: resuming)
                        } else {
                            try? await vm.start()
                        }
                    }
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
                    scenarioCatalog: container.scenarioCatalog,
                    debriefPersister: container.debriefRepository
                )
                DebriefView(viewModel: DebriefViewModel(
                    analyzer: analyzer,
                    sessionId: sessionId,
                    weakSpotPersister: container.weakSpotRepository,
                    audioPlayback: container.makeAudioPlayback(),
                    audioRoot: container.storageLayout.rootDirectory
                ))
            case .history:
                SessionsHistoryView(
                    viewModel: SessionsHistoryViewModel(
                        persister: container.sessionRepository,
                        audioPersister: container.audioFileStore,
                        catalog: container.scenarioCatalog
                    ),
                    onOpenDebrief: { id in selection = .debrief(sessionId: id) },
                    onContinue: { session in
                        selection = .session(
                            scenarioId: session.scenarioId,
                            mode: session.mode,
                            resuming: session.id
                        )
                    }
                )
            case .settings:
                SettingsView(viewModel: SettingsViewModel(persister: container.settingsRepository, store: settings))
            }
        }
        .navigationTitle(Theme.appName)
        .alert(
            "Pick up where you left off?",
            isPresented: Binding(
                get: { unfinishedSession != nil },
                set: { if !$0 { discardUnfinishedSession() } }
            ),
            presenting: unfinishedSession
        ) { session in
            Button("Continue") {
                guard let resuming = takeUnfinishedSession() else { return }
                selection = .session(
                    scenarioId: resuming.scenarioId,
                    mode: resuming.mode,
                    resuming: resuming.id
                )
            }
            Button("Discard", role: .destructive) {
                discardUnfinishedSession()
            }
        } message: { session in
            Text("\(scenarioTitle(for: session)) from "
                 + session.startedAt.formatted(date: .abbreviated, time: .shortened)
                 + " was never finished. Continuing keeps the conversation so far; "
                 + "discarding leaves it in your history as abandoned.")
        }
    }

    private func scenarioTitle(for session: Session) -> String {
        container.scenarioCatalog.scenario(id: session.scenarioId)?.title ?? session.scenarioId
    }
}
