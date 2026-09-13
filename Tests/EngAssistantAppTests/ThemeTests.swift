import Testing
import SwiftUI
import AppKit
import Core
@testable import EngAssistantApp

/// The type scale and the palette are the product here, so they're asserted
/// rather than eyeballed: the app is locked to a light appearance, and every
/// token has to be bigger than the macOS semantic style it replaced.
@Suite struct ThemeTypeScaleTests {
    @Test func everyTokenIsLargerThanWhatItReplaced() {
        for token in Theme.Size.macOSDefaults {
            #expect(
                token.now > token.before,
                "\(token.name) is \(token.now)pt, not larger than the \(token.before)pt it replaced"
            )
        }
    }

    @Test func bodyTextIsComfortablyReadable() {
        // The transcript is the thing you actually read; 16pt is the floor.
        #expect(Theme.Size.body >= 16)
    }

    @Test func scaleRampIsMonotonic() {
        let ramp: [CGFloat] = [
            Theme.Size.microLabel,
            Theme.Size.caption,
            Theme.Size.secondaryBody,
            Theme.Size.body,
            Theme.Size.cardTitle,
            Theme.Size.sectionTitle,
            Theme.Size.appTitle,
        ]
        #expect(ramp == ramp.sorted(), "the ramp should increase step by step: \(ramp)")
        #expect(Set(ramp).count == ramp.count, "two steps of the ramp collide: \(ramp)")
    }

    @Test func textScaleMultipliesEveryToken() {
        // Sanity-check the one knob: doubling would double a token's size.
        #expect(Theme.Size.scaled(10) == (10 * Theme.textScale).rounded())
        #expect(Theme.textScale > 0)
    }
}

/// Every colour is a light/dark pair resolved at draw time, so each assertion
/// has to name the appearance it's checking — resolving one in the test process
/// would otherwise just pick up whatever the Mac is set to.
@MainActor
@Suite struct ThemePaletteTests {
    private static let appearances: [(name: String, appearance: NSAppearance)] = [
        ("light", NSAppearance(named: .aqua)!),
        ("dark", NSAppearance(named: .darkAqua)!),
    ]

    /// WCAG relative luminance, 0 (black) to 1 (white), resolved under a
    /// specific appearance. The channel values have to be linearized first —
    /// using the gamma-encoded components directly overstates luminance for
    /// mid-tones and understates contrast.
    private static func luminance(_ color: Color, in appearance: NSAppearance) -> CGFloat {
        var result: CGFloat = -1
        appearance.performAsCurrentDrawingAppearance {
            guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            func linear(_ channel: CGFloat) -> CGFloat {
                channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            result = 0.2126 * linear(srgb.redComponent)
                + 0.7152 * linear(srgb.greenComponent)
                + 0.0722 * linear(srgb.blueComponent)
        }
        return result
    }

    private static func contrast(_ a: Color, _ b: Color, in appearance: NSAppearance) -> CGFloat {
        let la = luminance(a, in: appearance) + 0.05
        let lb = luminance(b, in: appearance) + 0.05
        return max(la, lb) / min(la, lb)
    }

    /// Every colour used as text sits on a card, so every one needs the 4.5:1
    /// normal-text threshold — in both appearances.
    private static var textColors: [(String, Color)] {
        var colors: [(String, Color)] = [
            ("textPrimary", Theme.textPrimary),
            ("textSecondary", Theme.textSecondary),
            ("brand", Theme.brand),
            ("highlight", Theme.highlight),
            ("success", Theme.success),
            ("warning", Theme.warning),
            ("danger", Theme.danger),
        ]
        colors += WeakSpotCategory.allCases.map {
            ("correction:\($0.rawValue)", Theme.correctionColor($0))
        }
        colors += ScenarioDomain.allCases.map {
            ("domain:\($0.rawValue)", Theme.domainColor($0))
        }
        return colors
    }

    @Test func lightAppearanceHasLightSurfacesAndDarkText() {
        let light = NSAppearance(named: .aqua)!
        #expect(Self.luminance(Theme.cardSurface, in: light) > 0.9)
        #expect(Self.luminance(Theme.mutedSurface, in: light) > 0.85)
        #expect(Self.luminance(Theme.textPrimary, in: light) < 0.2)
    }

    /// The whole point of the theme switch: the same tokens have to flip, not
    /// just sit there being light.
    @Test func darkAppearanceHasDarkSurfacesAndLightText() {
        let dark = NSAppearance(named: .darkAqua)!
        #expect(Self.luminance(Theme.cardSurface, in: dark) < 0.1)
        #expect(Self.luminance(Theme.mutedSurface, in: dark) < 0.1)
        #expect(Self.luminance(Theme.textPrimary, in: dark) > 0.7)
    }

    @Test func surfacesActuallyDifferBetweenAppearances() {
        let light = NSAppearance(named: .aqua)!
        let dark = NSAppearance(named: .darkAqua)!
        // A token that resolved the same in both would mean the dynamic
        // provider isn't being consulted at all.
        #expect(Self.luminance(Theme.cardSurface, in: light)
                != Self.luminance(Theme.cardSurface, in: dark))
        #expect(Self.luminance(Theme.textPrimary, in: light)
                != Self.luminance(Theme.textPrimary, in: dark))
    }

    /// Cards sit above the page in both appearances — same relationship, not
    /// the same direction of lightness.
    @Test func cardStandsApartFromThePageBehindIt() {
        for (name, appearance) in Self.appearances {
            let card = Self.luminance(Theme.cardSurface, in: appearance)
            let page = Self.luminance(Theme.mutedSurface, in: appearance)
            #expect(card != page, "card and page are identical in \(name)")
        }
    }

    @Test func everyTextColorMeetsContrastInBothAppearances() {
        for (appearanceName, appearance) in Self.appearances {
            for (colorName, color) in Self.textColors {
                let ratio = Self.contrast(color, Theme.cardSurface, in: appearance)
                #expect(
                    ratio >= 4.5,
                    "\(colorName) only reaches \(ratio):1 on a \(appearanceName) card"
                )
            }
        }
    }

    /// The separator is what gives a card an edge against the page, so it has
    /// to be distinguishable from both — darker in light mode, lighter in dark.
    @Test func separatorIsVisibleAgainstBothSurfaces() {
        let light = NSAppearance(named: .aqua)!
        #expect(Self.luminance(Theme.separator, in: light) < Self.luminance(Theme.cardSurface, in: light))

        let dark = NSAppearance(named: .darkAqua)!
        #expect(Self.luminance(Theme.separator, in: dark) > Self.luminance(Theme.cardSurface, in: dark))
    }
}

@MainActor
@Suite struct ThemeHeroGradientTests {
    private static func luminance(_ color: Color) -> CGFloat {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return -1 }
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(srgb.redComponent)
            + 0.7152 * linear(srgb.greenComponent)
            + 0.0722 * linear(srgb.blueComponent)
    }

    /// The onboarding hero is the one place white text is used, and it sits on
    /// the gradient — so every stop has to carry it, not just the dark end.
    @Test func whiteTextClearsContrastAtEveryGradientStop() {
        for stop in Theme.gradientStops {
            let ratio = 1.05 / (Self.luminance(stop) + 0.05)
            #expect(ratio >= 4.5, "white text only reaches \(ratio):1 on a gradient stop")
        }
    }
}
