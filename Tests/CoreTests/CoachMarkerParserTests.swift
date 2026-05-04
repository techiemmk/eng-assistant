import Testing
@testable import Core

@Suite struct CoachMarkerParserTests {
    @Test func parsesEmptyTextAsEmptyResult() {
        let result = CoachMarkerParser.parse("")
        #expect(result.spokenText == "")
        #expect(result.corrections.isEmpty)
    }

    @Test func passesThroughTextWithNoMarkers() {
        let result = CoachMarkerParser.parse("Hello there. How are you?")
        #expect(result.spokenText == "Hello there. How are you?")
        #expect(result.corrections.isEmpty)
    }

    @Test func extractsSingleMarkerAndStripsItFromSpokenText() {
        let input = "That's interesting. [[coach: try 'fascinating' instead]] What else?"
        let result = CoachMarkerParser.parse(input)
        #expect(result.spokenText == "That's interesting.  What else?")
        #expect(result.corrections == [Correction(message: "try 'fascinating' instead")])
    }

    @Test func extractsMultipleMarkersInOrder() {
        let input = "Sure. [[coach: 'sure' is filler]] I'll help. [[coach: 'I will help' is more direct]]"
        let result = CoachMarkerParser.parse(input)
        #expect(result.spokenText == "Sure.  I'll help. ")
        #expect(result.corrections == [
            Correction(message: "'sure' is filler"),
            Correction(message: "'I will help' is more direct"),
        ])
    }

    @Test func malformedMarkerWithoutClosingIsLeftIntact() {
        let input = "Hi [[coach: never closed and that's OK"
        let result = CoachMarkerParser.parse(input)
        #expect(result.spokenText == "Hi [[coach: never closed and that's OK")
        #expect(result.corrections.isEmpty)
    }

    @Test func emptyMarkerIsRecordedAsEmptyCorrection() {
        let result = CoachMarkerParser.parse("Hi. [[coach: ]] Bye.")
        #expect(result.spokenText == "Hi.  Bye.")
        #expect(result.corrections == [Correction(message: "")])
    }
}
