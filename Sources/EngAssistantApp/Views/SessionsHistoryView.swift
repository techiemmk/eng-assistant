import SwiftUI
import Core

public struct SessionsHistoryView: View {
    @ObservedObject var viewModel: SessionsHistoryViewModel
    let onSelect: (UUID) -> Void

    public init(viewModel: SessionsHistoryViewModel, onSelect: @escaping (UUID) -> Void) {
        self.viewModel = viewModel
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.brand)
                Text("Sessions").font(Theme.appTitle)
            }
            .padding(20)

            if viewModel.isLoading {
                Spacer()
                ProgressView().controlSize(.large)
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
                            SessionRowCard(session: session) {
                                onSelect(session.id)
                            }
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
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.brand.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.brand)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.scenarioId)
                        .font(Theme.cardTitle)
                    HStack(spacing: 8) {
                        Label(session.startedAt.formatted(date: .abbreviated, time: .shortened),
                              systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        statusBadge
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Theme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var statusBadge: some View {
        let color: Color = {
            switch session.status {
            case .active: return Theme.brand
            case .ended: return .green
            case .abandoned: return .gray
            }
        }()
        return Text(session.status.rawValue)
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
