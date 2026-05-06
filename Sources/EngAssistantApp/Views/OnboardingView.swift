import SwiftUI

public struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let onDone: () -> Void

    public init(viewModel: OnboardingViewModel, onDone: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDone = onDone
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to EngAssistant").font(.largeTitle).bold()
            Text("Let's make sure your Mac is ready for voice conversation practice. Audio and conversations stay on your machine.")
                .foregroundStyle(.secondary)

            checkRow(label: "Ollama running", status: viewModel.ollamaStatus)
            checkRow(label: "Microphone permission", status: viewModel.micStatus)

            HStack {
                Button("Run checks") {
                    Task { await viewModel.runChecks() }
                }
                Spacer()
                Button("Continue") {
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.allOK)
            }
        }
        .padding(28)
        .frame(width: 520, height: 360)
        .task { await viewModel.runChecks() }
    }

    private func checkRow(label: String, status: OnboardingViewModel.CheckStatus) -> some View {
        HStack(spacing: 10) {
            switch status {
            case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            case .running: ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if case let .failed(msg) = status {
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}
