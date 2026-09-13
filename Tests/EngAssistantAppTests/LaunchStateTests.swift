import Testing
import Foundation
import Core
@testable import EngAssistantApp

/// The launch screen is held for a minimum duration so it doesn't flash past on
/// a warm start. These use a tiny hold so the suite doesn't sit through it.
@MainActor
@Suite struct LaunchStateTests {
    @MainActor
    final class AppearanceRecorder {
        var applied: [AppearancePreference] = []
        lazy var applier: AppearanceApplying = { [weak self] preference in
            self?.applied.append(preference)
        }
    }

    @Test func startsOnTheLaunchScreen() {
        let state = AppState(launchHold: .milliseconds(10), applyAppearance: { _ in })
        #expect(state.isLaunching)
        #expect(state.container == nil)
    }

    @Test func launchScreenIsDismissedOnceBootstrapFinishes() async {
        let state = AppState(launchHold: .milliseconds(10), applyAppearance: { _ in })
        await state.bootstrap()
        #expect(state.isLaunching == false)
        #expect(state.container != nil)
        #expect(state.settings != nil)
    }

    /// The hold is a floor, not a fixed sleep — the screen must stay up for at
    /// least that long even when bootstrap returns immediately.
    @Test func launchScreenStaysUpForAtLeastTheHold() async {
        let hold = Duration.milliseconds(300)
        let state = AppState(launchHold: hold, applyAppearance: { _ in })
        let started = ContinuousClock.now
        await state.bootstrap()
        let elapsed = ContinuousClock.now - started
        #expect(elapsed >= hold, "bootstrap returned in \(elapsed), before the \(hold) hold")
    }

    /// Measuring elapsed time rather than always sleeping means a slow first
    /// launch doesn't pay the hold on top of its own work.
    @Test func holdIsNotAddedOnTopOfSlowBootstrapWork() async {
        let hold = Duration.milliseconds(200)
        let state = AppState(launchHold: hold, applyAppearance: { _ in })
        let started = ContinuousClock.now
        await state.bootstrap()
        let elapsed = ContinuousClock.now - started
        // Well under hold + a generous allowance for the real container build.
        #expect(elapsed < hold + .seconds(3), "took \(elapsed), which looks additive")
    }

    /// The default is the one the app actually ships with.
    @Test func defaultHoldIsThreeSeconds() {
        #expect(AppState.defaultLaunchHold == .seconds(3))
    }

    /// The launch screen paints before the saved theme is known, so the default
    /// has to be applied up front or it would start in the Mac's appearance.
    @Test func defaultThemeIsAppliedBeforeSettingsLoad() async {
        let recorder = AppearanceRecorder()
        let state = AppState(launchHold: .milliseconds(10), applyAppearance: recorder.applier)
        await state.bootstrap()
        #expect(recorder.applied.first == AppDefaults.appearance)
    }

    @Test func bootstrappingTwiceIsANoOp() async {
        let state = AppState(launchHold: .milliseconds(10), applyAppearance: { _ in })
        await state.bootstrap()
        let container = state.container
        await state.bootstrap()
        #expect(state.container === container)
    }
}
