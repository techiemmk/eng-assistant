import Foundation
import Core
import Adapters

/// Turns adapter and engine errors into something a user can act on. The live
/// session screen used to print raw Swift error values, so a missing Ollama
/// model surfaced as "Turn failed: statusCode(404)".
public enum FriendlyError {
    public static func message(for error: Error) -> String {
        switch error {
        case let engineError as SessionEngineError:
            return message(for: engineError)
        case let localized as LocalizedError:
            if let description = localized.errorDescription { return description }
            return "\(error)"
        case HTTPClientError.transport:
            return "Couldn't reach Ollama on localhost:11434. Start it with `ollama serve`."
        case HTTPClientError.statusCode(let code):
            return "Ollama replied with HTTP \(code)."
        case HTTPClientError.invalidResponse:
            return "Ollama sent a response the app couldn't read."
        case let urlError as URLError where urlError.code == .cannotConnectToHost
            || urlError.code == .cannotFindHost
            || urlError.code == .networkConnectionLost:
            return "Couldn't reach Ollama on localhost:11434. Start it with `ollama serve`."
        default:
            return "\(error)"
        }
    }

    private static func message(for error: SessionEngineError) -> String {
        switch error {
        case .notStarted:
            return "The session hasn't started yet."
        case .alreadyCapturing:
            return "The microphone is already recording."
        case .notCapturing:
            return "The microphone wasn't recording."
        case .noSpeechCaptured:
            return "Didn't catch any speech — check your input device and try again."
        }
    }
}
