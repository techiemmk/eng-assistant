import SwiftUI
import Core

/// The screen the app opens on while it wires itself up: opens the database,
/// runs migrations, loads settings and the scenario catalog, and sweeps old
/// audio. That work is usually near-instant, so the view is held for a minimum
/// duration (see `AppState.launchHold`) rather than flashing past.
///
/// Everything here is static except the spinner. A splash screen is the first
/// impression, and animated wording — a pulsing mark, a label whose dots grow
/// and shrink — reads as restless rather than polished. The standard
/// indeterminate indicator is enough to say work is happening.
struct LaunchView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                Image(systemName: Theme.appIconSymbol)
                    .font(Theme.heroIcon)
                    .foregroundStyle(.white)

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

            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Getting things ready")
                    .font(Theme.secondaryBody)
                    .foregroundStyle(.white.opacity(0.95))
            }
            .padding(.bottom, 40)
        }
        .frame(width: 620, height: 460)
        .background(Theme.brandGradient)
    }
}
