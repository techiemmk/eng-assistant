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
        VStack(alignment: .leading) {
            Text("Sessions").font(.largeTitle).bold().padding()
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.sessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "calendar")
            } else {
                List(viewModel.sessions) { session in
                    Button {
                        onSelect(session.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(session.scenarioId).bold()
                                Text(session.startedAt, style: .date)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(session.status.rawValue)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
        .task {
            try? await viewModel.load()
        }
    }
}
