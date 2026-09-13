import SwiftUI
import Core

/// The screen the app opens on while it wires itself up: opens the database,
/// runs migrations, loads settings and the scenario catalog, and sweeps old
/// audio. That work is usually near-instant, so the view is held for a minimum
/// duration (see `AppState.launchHold`) rather than flashing past.
struct LaunchView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                Image(systemName: Theme.appIconSymbol)
                    .font(Theme.heroIcon)
                    .foregroundStyle(.white)
                    // A slow, single pulse — the wait is short, so a busy
                    // animation here would read as a problem.
                    .symbolEffect(.pulse, options: .repeating)

                Text(Theme.appName)
                    .font(Theme.appTitle)
                    .foregroundStyle(.white)

                Text("Practice spoken English with a private, on-device AI partner.")
                    .font(Theme.secondaryBody)
                    .foregroundStyle(.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            ActivityLabel(
                text: "Getting things ready",
                systemImage: "circle.dotted",
                color: .white,
                font: Theme.secondaryBody
            )
            .padding(.bottom, 40)
        }
        .frame(width: 620, height: 460)
        .background(Theme.brandGradient)
    }
}
