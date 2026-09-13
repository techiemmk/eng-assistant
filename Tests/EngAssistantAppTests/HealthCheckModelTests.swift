import Testing
import Foundation
@testable import EngAssistantApp

/// The setup wizard used to pass as long as Ollama answered at all, so a server
/// with no models pulled looked healthy and then 404'd on the first turn.
@Suite struct HealthCheckModelTests {
    private static func tags(_ json: String) -> HealthCheck {
        HealthCheck(probe: { _ in true }, bodyProbe: { _ in Data(json.utf8) })
    }

    private static let baseURL = URL(string: "http://localhost:11434")!

    @Test func listsInstalledModels() async {
        let check = Self.tags(#"{"models":[{"name":"qwen2.5:7b-instruct"},{"name":"llama3.2:latest"}]}"#)
        let models = await check.localModels(baseURL: Self.baseURL)
        #expect(models == ["qwen2.5:7b-instruct", "llama3.2:latest"])
    }

    /// Hosted models show up in `/api/tags` but need an Ollama subscription to
    /// answer, so counting them as installed is exactly how a green check turns
    /// into a 402 mid-conversation.
    @Test func cloudModelsAreNotCountedAsLocal() async {
        let check = Self.tags("""
        {"models":[
          {"name":"minimax-m3:cloud","remote_host":"https://ollama.com"},
          {"name":"gpt-oss:cloud"},
          {"name":"qwen2.5:7b-instruct"}
        ]}
        """)
        let models = await check.localModels(baseURL: Self.baseURL)
        #expect(models == ["qwen2.5:7b-instruct"])
    }

    @Test func modelStatusIsNotInstalledWhenOnlyCloudModelsExist() async {
        let check = Self.tags(#"{"models":[{"name":"minimax-m3:cloud","remote_host":"https://ollama.com"}]}"#)
        let status = await check.modelStatus(baseURL: Self.baseURL, model: "qwen2.5:7b-instruct")
        #expect(status?.installed == false)
        #expect(status?.available.isEmpty == true)
    }

    @Test func modelStatusMatchesExactName() async {
        let check = Self.tags(#"{"models":[{"name":"qwen2.5:7b-instruct"}]}"#)
        let status = await check.modelStatus(baseURL: Self.baseURL, model: "qwen2.5:7b-instruct")
        #expect(status?.installed == true)
    }

    /// `ollama run qwen2.5` resolves to `qwen2.5:latest`, so an untagged name in
    /// Settings shouldn't be reported as missing.
    @Test func modelStatusMatchesUntaggedName() async {
        let check = Self.tags(#"{"models":[{"name":"llama3.2:latest"}]}"#)
        let status = await check.modelStatus(baseURL: Self.baseURL, model: "llama3.2")
        #expect(status?.installed == true)
    }

    @Test func modelStatusIsNilWhenTheListCannotBeRead() async {
        let check = HealthCheck(probe: { _ in false }, bodyProbe: { _ in nil })
        let status = await check.modelStatus(baseURL: Self.baseURL, model: "any")
        #expect(status == nil)
    }

    @Test func malformedTagsBodyYieldsNoList() async {
        let check = Self.tags("not json")
        #expect(await check.localModels(baseURL: Self.baseURL) == nil)
    }
}

@Suite struct OnboardingModelCheckTests {
    private static let baseURL = URL(string: "http://localhost:11434")!

    @MainActor
    private static func viewModel(tags: String, modelName: String) -> OnboardingViewModel {
        OnboardingViewModel(
            healthCheck: HealthCheck(probe: { _ in true }, bodyProbe: { _ in Data(tags.utf8) }),
            locator: STTLocator(executableCandidates: []),
            baseURL: baseURL,
            modelName: modelName
        )
    }

    @MainActor
    @Test func failsWhenNoLocalModelIsInstalled() async {
        let vm = Self.viewModel(
            tags: #"{"models":[{"name":"minimax-m3:cloud","remote_host":"https://ollama.com"}]}"#,
            modelName: "qwen2.5:7b-instruct"
        )
        await vm.runChecks()
        #expect(vm.ollamaStatus == .ok)
        guard case let .failed(message) = vm.modelStatus else {
            Issue.record("expected the model check to fail, got \(vm.modelStatus)")
            return
        }
        #expect(message.contains("ollama pull qwen2.5:7b-instruct"))
        #expect(vm.allOK == false)
    }

    @MainActor
    @Test func passesWhenTheConfiguredModelIsInstalled() async {
        let vm = Self.viewModel(
            tags: #"{"models":[{"name":"qwen2.5:7b-instruct"}]}"#,
            modelName: "qwen2.5:7b-instruct"
        )
        await vm.runChecks()
        #expect(vm.modelStatus == .ok)
    }

    @MainActor
    @Test func listsAlternativesWhenADifferentModelIsInstalled() async {
        let vm = Self.viewModel(
            tags: #"{"models":[{"name":"llama3.2:latest"}]}"#,
            modelName: "qwen2.5:7b-instruct"
        )
        await vm.runChecks()
        guard case let .failed(message) = vm.modelStatus else {
            Issue.record("expected the model check to fail, got \(vm.modelStatus)")
            return
        }
        #expect(message.contains("llama3.2:latest"))
    }

    @MainActor
    @Test func setModelNameTargetsTheConfiguredModel() async {
        let vm = Self.viewModel(
            tags: #"{"models":[{"name":"llama3.2:latest"}]}"#,
            modelName: "qwen2.5:7b-instruct"
        )
        vm.setModelName("llama3.2:latest")
        await vm.runChecks()
        #expect(vm.modelStatus == .ok)
    }

    /// Speech-to-text is advisory: the wizard shouldn't trap the user behind it.
    @MainActor
    @Test func missingSTTDoesNotBlockGettingStarted() async {
        let vm = Self.viewModel(
            tags: #"{"models":[{"name":"qwen2.5:7b-instruct"}]}"#,
            modelName: "qwen2.5:7b-instruct"
        )
        await vm.runChecks()
        #expect(vm.sttStatus != .ok)
        // allOK ignores sttStatus; mic state depends on the host, so only assert
        // that STT isn't what's holding it back.
        #expect(vm.allOK == (vm.micStatus == .ok))
    }
}
