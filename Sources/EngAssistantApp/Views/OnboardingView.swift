import SwiftUI

public struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let onDone: () -> Void

    public init(viewModel: OnboardingViewModel, onDone: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Brand hero
            VStack(spacing: 14) {
                Image(systemName: Theme.appIconSymbol)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Welcome to \(Theme.appName)")
                    .font(Theme.appTitle)
                    .foregroundStyle(.white)
                Text("Practice spoken English with a private, on-device AI partner.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .background(Theme.brandGradient)

            // Checks
            VStack(alignment: .leading, spacing: 18) {
                Text("Quick setup")
                    .font(Theme.sectionTitle)
                    .padding(.bottom, 4)

                checkRow(
                    icon: "server.rack",
                    label: "Ollama running",
                    detail: "Local LLM server at localhost:11434",
                    status: viewModel.ollamaStatus
                )
                checkRow(
                    icon: "mic.circle.fill",
                    label: "Microphone permission",
                    detail: "Used only for in-session capture; audio stays local",
                    status: viewModel.micStatus
                )

                Spacer(minLength: 4)

                HStack {
                    Button {
                        Task { await viewModel.runChecks() }
                    } label: {
                        Label("Re-run checks", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button {
                        onDone()
                    } label: {
                        Label("Get started", systemImage: "arrow.right")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.allOK)
                }
            }
            .padding(28)
        }
        .frame(width: 560, height: 460)
        .task { await viewModel.runChecks() }
    }

    private func checkRow(
        icon: String,
        label: String,
        detail: String,
        status: OnboardingViewModel.CheckStatus
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusBackground(status))
                    .frame(width: 36, height: 36)
                statusIcon(status, fallback: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusForeground(status))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(.body, design: .rounded, weight: .semibold))
                if case let .failed(msg) = status {
                    Text(msg).font(.caption).foregroundStyle(.red)
                } else {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func statusIcon(_ status: OnboardingViewModel.CheckStatus, fallback: String) -> some View {
        switch status {
        case .unknown:
            Image(systemName: fallback)
        case .running:
            ProgressView().controlSize(.small)
        case .ok:
            Image(systemName: "checkmark")
        case .failed:
            Image(systemName: "xmark")
        }
    }

    private func statusBackground(_ status: OnboardingViewModel.CheckStatus) -> Color {
        switch status {
        case .unknown: return Color.gray.opacity(0.15)
        case .running: return Theme.brand.opacity(0.15)
        case .ok: return Color.green.opacity(0.18)
        case .failed: return Color.red.opacity(0.18)
        }
    }

    private func statusForeground(_ status: OnboardingViewModel.CheckStatus) -> Color {
        switch status {
        case .unknown: return .secondary
        case .running: return Theme.brand
        case .ok: return .green
        case .failed: return .red
        }
    }
}
