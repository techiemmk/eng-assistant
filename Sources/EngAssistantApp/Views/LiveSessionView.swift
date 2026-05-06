import SwiftUI
import Core

public struct LiveSessionView: View {
    @ObservedObject var viewModel: LiveSessionViewModel
    let onEnd: (UUID) -> Void

    public init(viewModel: LiveSessionViewModel, onEnd: @escaping (UUID) -> Void) {
        self.viewModel = viewModel
        self.onEnd = onEnd
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcriptScroll
            if let err = viewModel.lastError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
            controlBar
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.domainColor(viewModel.scenario.domain).opacity(0.20))
                    .frame(width: 44, height: 44)
                Image(systemName: Theme.domainIcon(viewModel.scenario.domain))
                    .foregroundStyle(Theme.domainColor(viewModel.scenario.domain))
                    .font(.system(size: 18, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.scenario.title).font(Theme.sectionTitle)
                Text(viewModel.scenario.persona)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    modeBadge
                    if viewModel.isProcessing {
                        Label("Working...", systemImage: "ellipsis")
                            .font(Theme.chip)
                            .foregroundStyle(Theme.brand)
                    } else if viewModel.isActive {
                        Label("Listening", systemImage: "circle.fill")
                            .font(Theme.chip)
                            .foregroundStyle(.green)
                    }
                }
            }
            Spacer()
        }
        .padding(18)
    }

    private var modeBadge: some View {
        let isCoach = viewModel.mode == .coach
        return Label(isCoach ? "Coach mode" : "Flow mode", systemImage: isCoach ? "lightbulb.fill" : "wind")
            .font(Theme.chip)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((isCoach ? Theme.highlight : Theme.brand).opacity(0.15))
            .foregroundStyle(isCoach ? Theme.highlight : Theme.brand)
            .clipShape(Capsule())
    }

    private var transcriptScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.transcript) { turn in
                        TurnBubbleView(turn: turn)
                            .id(turn.id)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .frame(maxHeight: .infinity)
            .background(Theme.mutedSurface)
            .onChange(of: viewModel.transcript.count) { _, _ in
                if let last = viewModel.transcript.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { try? await viewModel.runUserTurn() }
            } label: {
                Label("Push to talk", systemImage: "mic.fill")
                    .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.isActive || viewModel.isProcessing)

            Spacer()

            Button {
                Task {
                    if let id = try? await viewModel.end() {
                        onEnd(id)
                    }
                }
            } label: {
                Label("End session", systemImage: "stop.circle.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!viewModel.isActive)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.cardSurface)
    }
}

private struct TurnBubbleView: View {
    let turn: LiveSessionViewModel.DisplayTurn

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if turn.speaker == .user { Spacer(minLength: 40) }
            if turn.speaker == .ai { avatar }
            VStack(alignment: turn.speaker == .user ? .trailing : .leading, spacing: 6) {
                Text(turn.speaker == .user ? "You" : "AI")
                    .font(.caption).foregroundStyle(.secondary)
                Text(turn.text)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(turn.speaker == .user ? Theme.brand.opacity(0.18) : Theme.cardSurface)
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                ForEach(turn.corrections.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(Theme.highlight)
                            .font(.caption)
                        Text(turn.corrections[i].message)
                            .font(.caption)
                            .foregroundStyle(Theme.highlight)
                    }
                }
            }
            .frame(maxWidth: 480, alignment: turn.speaker == .user ? .trailing : .leading)
            if turn.speaker == .user { avatar }
            if turn.speaker == .ai { Spacer(minLength: 40) }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(turn.speaker == .user ? Theme.brand.opacity(0.18) : Color.gray.opacity(0.15))
                .frame(width: 28, height: 28)
            Image(systemName: turn.speaker == .user ? "person.fill" : "sparkles")
                .font(.caption)
                .foregroundStyle(turn.speaker == .user ? Theme.brand : .secondary)
        }
    }
}
