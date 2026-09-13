import Testing
import Foundation
import Core
@testable import Adapters

/// Ollama answers `/api/chat` with 404 when the model isn't pulled and 402 for
/// a hosted model the account can't use. Both used to reach the UI as
/// "statusCode(404)", which told the user nothing about the fix.
@Suite struct OllamaLLMErrorTests {
    private func llm(_ client: StubHTTPClient) -> OllamaLLM {
        OllamaLLM(httpClient: client, baseURL: URL(string: "http://localhost:11434")!)
    }

    @Test func missingModelBecomesAnActionableError() async throws {
        let client = StubHTTPClient()
        client.nextError = HTTPClientError.statusCode(404)
        await #expect(throws: OllamaLLMError.modelNotInstalled(model: "qwen2.5:7b-instruct")) {
            _ = try await llm(client).respond(
                messages: [ChatMessage(role: .user, content: "hi")],
                options: LLMOptions(modelName: "qwen2.5:7b-instruct")
            )
        }
    }

    @Test func missingModelErrorNamesThePullCommand() {
        let message = OllamaLLMError.modelNotInstalled(model: "qwen2.5:7b-instruct").errorDescription ?? ""
        #expect(message.contains("ollama pull qwen2.5:7b-instruct"))
    }

    @Test func paymentRequiredBecomesASubscriptionError() async throws {
        let client = StubHTTPClient()
        client.nextError = HTTPClientError.statusCode(402)
        await #expect(throws: OllamaLLMError.modelRequiresSubscription(model: "minimax-m3:cloud")) {
            _ = try await llm(client).respond(
                messages: [ChatMessage(role: .user, content: "hi")],
                options: LLMOptions(modelName: "minimax-m3:cloud")
            )
        }
    }

    /// Other statuses aren't setup problems, so they stay as transport errors.
    @Test func otherStatusCodesPassThroughUnchanged() async throws {
        let client = StubHTTPClient()
        client.nextError = HTTPClientError.statusCode(500)
        await #expect(throws: HTTPClientError.statusCode(500)) {
            _ = try await llm(client).respond(
                messages: [ChatMessage(role: .user, content: "hi")],
                options: LLMOptions(modelName: "m")
            )
        }
    }
}

@Suite struct WhisperLocalSTTPreflightTests {
    private static func stt(
        executableExists: Bool,
        modelExists: Bool
    ) -> WhisperLocalSTT {
        WhisperLocalSTT(
            runner: StubProcessRunner(),
            executablePath: "/opt/homebrew/bin/whisper-cli",
            modelPath: "/models/ggml-base.en.bin",
            fileProbe: .init(isExecutable: { _ in executableExists }, isReadable: { _ in modelExists })
        )
    }

    @Test func missingExecutableIsReportedBeforeLaunching() async throws {
        await #expect(throws: WhisperLocalSTTError.executableMissing(path: "/opt/homebrew/bin/whisper-cli")) {
            _ = try await Self.stt(executableExists: false, modelExists: true)
                .transcribe(audio: Data(repeating: 1, count: 64))
        }
    }

    @Test func missingModelIsReportedBeforeLaunching() async throws {
        await #expect(throws: WhisperLocalSTTError.modelMissing(path: "/models/ggml-base.en.bin")) {
            _ = try await Self.stt(executableExists: true, modelExists: false)
                .transcribe(audio: Data(repeating: 1, count: 64))
        }
    }

    @Test func missingExecutableErrorNamesTheBrewFormula() {
        let message = WhisperLocalSTTError.executableMissing(path: "/x").errorDescription ?? ""
        #expect(message.contains("brew install whisper-cpp"))
    }
}
