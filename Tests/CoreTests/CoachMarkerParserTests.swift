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

/// Coach markers can name the kind of mistake, and quote the user's own wrong
/// wording so the transcript can highlight it rather than only describing it.
@Suite struct CoachMarkerCategoryTests {
    @Test func parsesGrammarCategoryAndOffendingPhrase() {
        let input = "Nice. [[coach:grammar: try 'I finished' instead of 'I have finish']] What's next?"
        let result = CoachMarkerParser.parse(input)
        #expect(result.spokenText == "Nice.  What's next?")
        let correction = result.corrections.first
        #expect(correction?.category == .grammar)
        #expect(correction?.offendingText == "I have finish")
        #expect(correction?.message == "try 'I finished' instead of 'I have finish'")
    }

    @Test func parsesEveryKnownCategory() {
        for category in WeakSpotCategory.allCases {
            let result = CoachMarkerParser.parse("[[coach:\(category.rawValue): something]]")
            #expect(result.corrections.first?.category == category)
            #expect(result.corrections.first?.message == "something")
        }
    }

    @Test func categoryLabelIsCaseInsensitive() {
        let result = CoachMarkerParser.parse("[[coach:GRAMMAR: fix it]]")
        #expect(result.corrections.first?.category == .grammar)
    }

    /// Unlabelled markers stay valid — older prompts and sloppier models still
    /// produce them, and a tip without a category is better than a dropped tip.
    @Test func unlabelledMarkerKeepsFullMessageAndNoCategory() {
        let result = CoachMarkerParser.parse("[[coach: try 'fascinating' instead]]")
        #expect(result.corrections.first?.category == nil)
        #expect(result.corrections.first?.message == "try 'fascinating' instead")
    }

    /// A colon that isn't a category must not be eaten as one.
    @Test func unknownLabelIsNotTreatedAsACategory() {
        let result = CoachMarkerParser.parse("[[coach: note: watch your tense]]")
        #expect(result.corrections.first?.category == nil)
        #expect(result.corrections.first?.message == "note: watch your tense")
    }

    @Test func offendingPhraseIsNilWithoutAnInsteadOfClause() {
        let result = CoachMarkerParser.parse("[[coach:fluency: you paused a lot there]]")
        #expect(result.corrections.first?.offendingText == nil)
    }

    @Test func handlesDoubleAndCurlyQuotes() {
        let straight = CoachMarkerParser.parse(#"[[coach:grammar: say "she goes" instead of "she go"]]"#)
        #expect(straight.corrections.first?.offendingText == "she go")

        let curly = CoachMarkerParser.parse("[[coach:grammar: say \u{2018}she goes\u{2019} instead of \u{2018}she go\u{2019}]]")
        #expect(curly.corrections.first?.offendingText == "she go")
    }

    /// An apostrophe inside the quoted phrase must not end it early.
    @Test func apostropheInsidePhraseDoesNotTerminateIt() {
        let result = CoachMarkerParser.parse("[[coach:grammar: try 'I don't have' instead of 'I don't got']]")
        #expect(result.corrections.first?.offendingText == "I don't got")
    }

    @Test func multipleCategorisedMarkersKeepTheirOwnCategories() {
        let input = "[[coach:grammar: try 'went' instead of 'goed']] Right. [[coach:vocab: try 'exhausted' instead of 'very tired']]"
        let result = CoachMarkerParser.parse(input)
        #expect(result.corrections.count == 2)
        #expect(result.corrections[0].category == .grammar)
        #expect(result.corrections[0].offendingText == "goed")
        #expect(result.corrections[1].category == .vocab)
        #expect(result.corrections[1].offendingText == "very tired")
    }

    /// The spoken text is what reaches TTS, so markers must leave no residue.
    @Test func categorisedMarkersAreStrippedFromSpokenText() {
        let result = CoachMarkerParser.parse("[[coach:grammar: try 'went' instead of 'goed']]Sure thing.")
        #expect(!result.spokenText.contains("coach"))
        #expect(!result.spokenText.contains("grammar"))
        #expect(result.spokenText == "Sure thing.")
    }
}

/// Not every fix is a substitution. Filler words are deleted, and "try 'X'
/// instead of 'X'" is what a model produces when forced into the wrong template.
@Suite struct CoachMarkerDeletionTests {
    @Test func dropStyleMarkerYieldsTheWordToHighlight() {
        let result = CoachMarkerParser.parse("[[coach:filler: drop 'actually']]")
        let correction = result.corrections.first
        #expect(correction?.category == .filler)
        #expect(correction?.offendingText == "actually")
    }

    @Test func avoidAndCutAlsoNameThePhrase() {
        #expect(CoachMarkerParser.parse("[[coach:filler: avoid 'you know']]")
            .corrections.first?.offendingText == "you know")
        #expect(CoachMarkerParser.parse("[[coach:filler: cut 'sort of']]")
            .corrections.first?.offendingText == "sort of")
    }

    /// When both leads appear, the substitution target wins — it's the specific
    /// wording being replaced, not an aside.
    @Test func insteadOfWinsOverDropWhenBothAppear() {
        let result = CoachMarkerParser.parse(
            "[[coach:grammar: try 'I finished' instead of 'I have finish' and drop 'like']]"
        )
        #expect(result.corrections.first?.offendingText == "I have finish")
    }

    @Test func unquotedAdviceStillYieldsNoHighlight() {
        let result = CoachMarkerParser.parse("[[coach:filler: drop the filler words]]")
        #expect(result.corrections.first?.offendingText == nil)
        #expect(result.corrections.first?.message == "drop the filler words")
    }
}
