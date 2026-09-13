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
                    .font(Theme.heroIcon)
                    .foregroundStyle(.white)
                Text("Welcome to \(Theme.appName)")
                    .font(Theme.appTitle)
                    .foregroundStyle(.white)
                Text("Practice spoken English with a private, on-device AI partner.")
                    .font(Theme.secondaryBody)
                    .foregroundStyle(.white.opacity(0.95))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .background(Theme.brandGradient)

            // Checks
            VStack(alignment: .leading, spacing: 12) {
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
                    icon: "brain.head.profile",
                    label: "Language model installed",
                    detail: "A local model Ollama can actually run",
                    status: viewModel.modelStatus
                )
                checkRow(
                    icon: "mic.circle.fill",
                    label: "Microphone permission",
                    detail: "Used only for in-session capture; audio stays local",
                    status: viewModel.micStatus
                )
                checkRow(
                    icon: "waveform.badge.mic",
                    label: "Speech-to-text (optional)",
                    detail: "whisper.cpp + a ggml model, so the AI hears your words",
                    status: viewModel.sttStatus
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
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.allOK)
                }
            }
            .padding(28)
        }
        .frame(width: 660, height: 760)
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
                    .frame(width: 42, height: 42)
                statusIcon(status, fallback: icon)
                    .font(Theme.rowIcon)
                    .foregroundStyle(statusForeground(status))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.cardTitle)
                if case let .failed(msg) = status {
                    Text(msg).font(Theme.caption).foregroundStyle(Theme.danger)
                } else {
                    Text(detail).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator, lineWidth: 1))
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
        case .unknown: return Theme.separator.opacity(0.55)
        case .running: return Theme.brand.opacity(0.15)
        case .ok: return Theme.success.opacity(0.15)
        case .failed: return Theme.danger.opacity(0.13)
        }
    }

    private func statusForeground(_ status: OnboardingViewModel.CheckStatus) -> Color {
        switch status {
        case .unknown: return Theme.textSecondary
        case .running: return Theme.brand
        case .ok: return Theme.success
        case .failed: return Theme.danger
        }
    }
}
