import Foundation

/// English fillers commonly produced by ESL speakers practicing fluency.
/// All entries are lowercase. Multi-word phrases are matched as whole-word
/// sequences (whitespace-separated) — punctuation is stripped before matching.
public enum FillerDictionary {
    public static let singleWord: Set<String> = [
        "um", "uh", "uhh", "ehm", "er", "erm",
        "like", "actually", "basically", "literally",
        "right", "okay", "ok", "well", "anyway",
    ]

    public static let phrases: [[String]] = [
        ["you", "know"],
        ["i", "mean"],
        ["sort", "of"],
        ["kind", "of"],
        ["i", "guess"],
        ["or", "something"],
        ["or", "whatever"],
    ]
}
