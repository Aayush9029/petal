public struct S1MiniControls: Sendable, Equatable {
    public var styling: S1MiniStyling
    public var structure: S1MiniStructure
    public var context: S1MiniContext
    public var systemPrompt: String

    /// S1-mini was trained on this exact wording. Other text can make the model garble its output.
    public static let defaultSystemPrompt = "You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text."

    public init(
        styling: S1MiniStyling = .semiFormal,
        structure: S1MiniStructure = .prose,
        context: S1MiniContext = .general,
        systemPrompt: String = Self.defaultSystemPrompt
    ) {
        self.styling = styling
        self.structure = structure
        self.context = context
        self.systemPrompt = systemPrompt
    }

    public var controlLine: String {
        "[Styling: \(styling.rawValue)] [Structure: \(structure.rawValue)] [Context: \(context.rawValue)]"
    }
}
