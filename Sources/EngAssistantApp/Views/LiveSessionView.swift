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
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.scenario.title).font(.title).bold()
                Text(viewModel.scenario.persona)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(viewModel.mode == .flow ? "Flow mode" : "Coach mode")
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.gray.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.transcript) { turn in
                        TurnBubbleView(turn: turn)
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: .infinity)
            .background(.gray.opacity(0.05))

            if let err = viewModel.lastError {
                Text(err).foregroundStyle(.red).font(.caption).padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button {
                    Task { try? await viewModel.runUserTurn() }
                } label: {
                    Label("Push to talk", systemImage: "mic.fill")
                        .frame(minWidth: 160)
                }
                .controlSize(.large)
                .disabled(!viewModel.isActive || viewModel.isProcessing)

                Spacer()

                Button("End Session") {
                    Task {
                        if let id = try? await viewModel.end() {
                            onEnd(id)
                        }
                    }
                }
                .controlSize(.large)
                .disabled(!viewModel.isActive)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(minWidth: 600, minHeight: 480)
    }
}

private struct TurnBubbleView: View {
    let turn: LiveSessionViewModel.DisplayTurn

    var body: some View {
        HStack(alignment: .top) {
            if turn.speaker == .user { Spacer() }
            VStack(alignment: turn.speaker == .user ? .trailing : .leading, spacing: 4) {
                Text(turn.speaker == .user ? "You" : "AI")
                    .font(.caption).foregroundStyle(.secondary)
                Text(turn.text)
                    .padding(10)
                    .background(turn.speaker == .user ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if !turn.corrections.isEmpty {
                    ForEach(turn.corrections.indices, id: \.self) { i in
                        Text("\u{1F4A1} \(turn.corrections[i].message)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: 460, alignment: turn.speaker == .user ? .trailing : .leading)
            if turn.speaker == .ai { Spacer() }
        }
    }
}
