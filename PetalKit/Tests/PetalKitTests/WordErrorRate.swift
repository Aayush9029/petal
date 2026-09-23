import Foundation

/// Word error rate after light normalization, so "3:30" and "three thirty" count as the same words.
enum WordErrorRate {
    static func errors(reference: String, hypothesis: String) -> (errors: Int, words: Int) {
        let ref = normalize(reference)
        let hyp = normalize(hypothesis)
        return (editDistance(ref, hyp), ref.count)
    }

    static func normalize(_ text: String) -> [String] {
        var text = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        for (symbol, word) in [("%", " percent "), ("&", " and "), (":", " "), ("-", " "), ("/", " ")] {
            text = text.replacingOccurrences(of: symbol, with: word)
        }
        let kept = text.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == " " ? Character($0) : " " }
        return String(kept)
            .split(separator: " ")
            .flatMap { token -> [String] in
                let token = token.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                guard !token.isEmpty else { return [] }
                return numberWords(token) ?? [token.replacingOccurrences(of: ".", with: "")]
            }
            .filter { !$0.isEmpty }
    }

    private static func numberWords(_ token: String) -> [String]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }), let whole = Int(parts[0]) else { return nil }
        var words = cardinal(whole)
        // "3.30" is how some models write the time "three thirty".
        if parts.count == 2, parts[1].count == 2, (1 ... 12).contains(whole), let minutes = Int(parts[1]), minutes >= 10 {
            return words + cardinal(minutes)
        }
        if parts.count == 2 {
            words.append("point")
            words += parts[1].compactMap { $0.wholeNumberValue }.flatMap(cardinal)
        }
        return words
    }

    private static let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                               "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    private static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    private static func cardinal(_ n: Int) -> [String] {
        switch n {
        case ..<20: [ones[n]]
        case ..<100: [tens[n / 10]] + (n % 10 == 0 ? [] : [ones[n % 10]])
        case ..<1000: [ones[n / 100], "hundred"] + (n % 100 == 0 ? [] : cardinal(n % 100))
        case ..<1_000_000: cardinal(n / 1000) + ["thousand"] + (n % 1000 == 0 ? [] : cardinal(n % 1000))
        default: [String(n)]
        }
    }

    private static func editDistance(_ a: [String], _ b: [String]) -> Int {
        var previous = Array(0 ... b.count)
        for (i, word) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, other) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (word == other ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
