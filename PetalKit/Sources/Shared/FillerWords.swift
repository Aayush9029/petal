public enum FillerWords {
    private static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "er", "erm", "ah", "hmm", "mm", "mhm"]

    public static func isFillerOnly(_ text: String) -> Bool {
        let words = text.lowercased()
            .split { !$0.isLetter }
            .map(String.init)
        return !words.isEmpty && words.allSatisfy(fillers.contains)
    }
}
