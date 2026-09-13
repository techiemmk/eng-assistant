import SwiftUI
import Core

public struct SessionsHistoryView: View {
    @ObservedObject var viewModel: SessionsHistoryViewModel
    let onOpenDebrief: (UUID) -> Void
    let onContinue: (Session) -> Void

    public init(
        viewModel: SessionsHistoryViewModel,
        onOpenDebrief: @escaping (UUID) -> Void,
        onContinue: @escaping (Session) -> Void
    ) {
        self.viewModel = viewModel
        self.onOpenDebrief = onOpenDebrief
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "clock.fill")
                    .font(Theme.screenIcon)
                    .foregroundStyle(Theme.brand)
                Text("Sessions").font(Theme.appTitle)
            }
            .padding(20)

            if viewModel.isLoading {
                Spacer()
                ActivityLabel(
                    text: "Loading sessions",
                    systemImage: "clock.arrow.circlepath",
                    font: Theme.body
                )
                .frame(maxWidth: .infinity)
                Spacer()
            } else if viewModel.sessions.isEmpty {
                Spacer()
                ContentUnavailableView {
                    Label("No sessions yet", systemImage: "bubble.left.and.bubble.right.fill")
                } description: {
                    Text("Start a session from the Practice tab — it'll show up here when you're done.")
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.sessions) { session in
                            SessionRowCard(
                                session: session,
                                title: viewModel.title(for: session),
                                canContinue: viewModel.canContinue(session),
                                onTap: { onOpenDebrief(session.id) },
                                onContinue: { onContinue(session) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .task {
            try? await viewModel.load()
        }
    }
}

private struct SessionRowCard: View {
    let session: Session
    let title: String
    let canContinue: Bool
    let onTap: () -> Void
    let onContinue: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.brand.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(Theme.rowIcon)
                        .foregroundStyle(Theme.brand)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.cardTitle)
                    HStack(spacing: 8) {
                        Label(session.startedAt.formatted(date: .abbreviated, time: .shortened),
                              systemImage: "calendar")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                        statusBadge
                    }
                }
                Spacer()
                Button(action: onContinue) {
                    Label("Continue", systemImage: "play.fill")
                        .font(Theme.chip)
                }
                .buttonStyle(.bordered)
                .disabled(!canContinue)
                .help(canContinue
                      ? "Pick this conversation up where it left off"
                      : "This scenario is no longer in the catalog")
                Image(systemName: "chevron.right")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(12)
            .background(Theme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var statusBadge: some View {
        let color: Color = {
            switch session.status {
            case .active: return Theme.brand
            case .ended: return Theme.success
            case .abandoned: return Theme.textSecondary
            }
        }()
        return Text(session.status.rawValue)
            .font(Theme.chip)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
