import Testing
@testable import Core

@Suite struct TextMetricsCalculatorTests {
    @Test func emptyTextProducesZeroMetrics() {
        let m = TextMetricsCalculator.calculate(text: "")
        #expect(m.totalWordCount == 0)
        #expect(m.uniqueWordCount == 0)
        #expect(m.fillerCount == 0)
        #expect(m.uniqueWordRatio == 0)
        #expect(m.fillerDensity == 0)
    }

    @Test func wordCountsSimpleSentence() {
        let m = TextMetricsCalculator.calculate(text: "The quick brown fox jumps")
        #expect(m.totalWordCount == 5)
        #expect(m.uniqueWordCount == 5)
        #expect(m.uniqueWordRatio == 1.0)
    }

    @Test func uniqueRatioReflectsRepetition() {
        let m = TextMetricsCalculator.calculate(text: "the the the cat cat sat")
        #expect(m.totalWordCount == 6)
        #expect(m.uniqueWordCount == 3)
        #expect(abs(m.uniqueWordRatio - 0.5) < 0.001)
    }

    @Test func detectsCommonFillers() {
        let m = TextMetricsCalculator.calculate(text: "Um, I think that, uh, you know, the project is going well.")
        // Four fillers: "um", "uh", "you know", "well". (you-know is one phrase.)
        #expect(m.fillerCount == 4)
        #expect(m.fillerDensity > 0)
    }

    @Test func caseInsensitiveAndStripsBasicPunctuation() {
        let m = TextMetricsCalculator.calculate(text: "Like, LIKE, like!")
        #expect(m.fillerCount == 3)
    }

    @Test func multiwordFillersDetected() {
        let m = TextMetricsCalculator.calculate(text: "I mean, you know, sort of, kind of finished it.")
        // "I mean", "you know", "sort of", "kind of" — four phrase-fillers.
        #expect(m.fillerCount == 4)
    }
}
