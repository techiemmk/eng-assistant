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

@Suite struct ThemeLightPaletteTests {
    /// WCAG relative luminance, 0 (black) to 1 (white). The channel values
    /// have to be linearized first — using the gamma-encoded components
    /// directly overstates luminance for mid-tones and understates contrast.
    private static func luminance(_ color: Color) -> CGFloat {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return -1 }
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(srgb.redComponent)
            + 0.7152 * linear(srgb.greenComponent)
            + 0.0722 * linear(srgb.blueComponent)
    }

    /// WCAG contrast ratio between two opaque colors.
    private static func contrast(_ a: Color, _ b: Color) -> CGFloat {
        let la = luminance(a) + 0.05
        let lb = luminance(b) + 0.05
        return max(la, lb) / min(la, lb)
    }

    @Test func surfacesAreLight() {
        #expect(Self.luminance(Theme.cardSurface) > 0.9)
        #expect(Self.luminance(Theme.mutedSurface) > 0.85)
    }

    /// Cards sit on the page background, so the two can't be the same value or
    /// the layout loses all structure.
    @Test func cardStandsApartFromThePageBehindIt() {
        #expect(Self.luminance(Theme.cardSurface) > Self.luminance(Theme.mutedSurface))
    }

    @Test func textIsDarkOnLightSurfaces() {
        #expect(Self.luminance(Theme.textPrimary) < 0.2)
        #expect(Self.luminance(Theme.textSecondary) < 0.5)
    }

    /// Both are used at 13-17pt, so both need the 4.5:1 normal-text threshold.
    @Test func textMeetsContrastOnCards() {
        #expect(Self.contrast(Theme.textPrimary, Theme.cardSurface) >= 4.5)
        #expect(Self.contrast(Theme.textSecondary, Theme.cardSurface) >= 4.5)
    }

    /// These are all used as small colored text on a white card, which is
    /// exactly where an accent picked for a dark background stops being
    /// legible — every one of these had to be darkened for the light theme.
    @Test func accentsStayLegibleAsTextOnWhite() {
        let accents: [(String, Color)] = [
            ("brand", Theme.brand),
            ("highlight", Theme.highlight),
            ("success", Theme.success),
            ("warning", Theme.warning),
            ("danger", Theme.danger),
        ]
        for (name, color) in accents {
            let ratio = Self.contrast(color, Theme.cardSurface)
            #expect(ratio >= 4.5, "\(name) only reaches \(ratio):1 on a card")
        }
    }

    @Test func correctionColorsStayLegibleAsTextOnWhite() {
        for category in WeakSpotCategory.allCases {
            let ratio = Self.contrast(Theme.correctionColor(category), Theme.cardSurface)
            #expect(ratio >= 4.5, "\(category.rawValue) only reaches \(ratio):1 on a card")
        }
    }

    @Test func domainColorsStayLegibleAsTextOnWhite() {
        for domain in ScenarioDomain.allCases {
            let ratio = Self.contrast(Theme.domainColor(domain), Theme.cardSurface)
            #expect(ratio >= 4.5, "\(domain.rawValue) only reaches \(ratio):1 on a card")
        }
    }

    /// The separator is what gives a white card an edge against the off-white
    /// page, so it has to be darker than both.
    @Test func separatorIsVisibleAgainstBothSurfaces() {
        #expect(Self.luminance(Theme.separator) < Self.luminance(Theme.mutedSurface))
        #expect(Self.luminance(Theme.separator) < Self.luminance(Theme.cardSurface))
    }
}

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
