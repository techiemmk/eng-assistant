import SwiftUI
import Core
import Persistence
import Adapters

@main
struct EngAssistantApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("EngAssistant") {
            Group {
                if !appState.didCompleteOnboarding {
                    OnboardingView(viewModel: appState.onboardingVM) {
                        appState.didCompleteOnboarding = true
                    }
                } else if let container = appState.container {
                    ContentView(container: container)
                } else {
                    ProgressView("Initializing...")
                }
            }
            .task {
                await appState.bootstrap()
            }
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var didCompleteOnboarding: Bool = false
    @Published var container: AppContainer?
    let onboardingVM = OnboardingViewModel()

    func bootstrap() async {
        guard container == nil else { return }
        do {
            let c = try AppContainer()
            container = c
            // Read retention setting and run sweeper in the background.
            let days: Int
            if let s = try c.settingsRepository.get(.audioRetentionDays), let d = Int(s) {
                days = d
            } else {
                days = 30
            }
            Task.detached {
                let sweeper = AudioRetentionSweeper(layout: c.storageLayout, retentionDays: days)
                _ = try? sweeper.sweep()
            }
        } catch {
            FileHandle.standardError.write(Data("[bootstrap] container init failed: \(error)\n".utf8))
        }
    }
}
