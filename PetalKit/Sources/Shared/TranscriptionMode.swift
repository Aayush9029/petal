public enum TranscriptionMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case verbatim
    case smart

    public var id: String { rawValue }

    /// Tuned on dictation with slang, file names, and code terms. Filler-only input must skip the model because it
    /// copies an example into the output.
    public static let defaultSmartPrompt = """
        Rewrite the transcript as clean written text. Delete fillers (um, uh, filler 'like') and repeated words. For self-corrections (no wait, actually, sorry), keep only the final version. Add punctuation and capital letters. Keep all other words and the speaker's tone, including slang (yo, cool, gonna, lol, dude); never make it formal or shorter. Never add words or ideas that the speaker did not say. Convert spoken code to written form: 'dot' is '.', 'underscore' is '_', 'dash dash' is '--', 'slash' is '/', 'at' in an email address is '@', numbers and versions are digits, and names of files, functions, commands, and products use their usual spelling.
        These examples show only the format. Never copy their words into the output:
        'um so can you like restart the the server' -> 'So, can you restart the server?'
        'open main dot py no wait utils dot py' -> 'Open utils.py.'
        'set retries to five no wait ten' -> 'Set retries to 10.'
        'lets sync at two actually make it three thirty' -> 'Let's sync at 3:30.'
        'email me at jo at gmail dot com' -> 'Email me at jo@gmail.com.'
        'call get user by id in user service dot ts' -> 'Call getUserById in UserService.ts.'
        'run npm install dash dash save dev' -> 'Run npm install --save-dev.'
        'we're gonna need python three point twelve on mac os lol' -> 'We're gonna need Python 3.12 on macOS, lol.'
        """

    public var displayName: String {
        switch self {
        case .verbatim:
            return "Verbatim"
        case .smart:
            return "Smart"
        }
    }

    public var description: String {
        switch self {
        case .verbatim:
            return "Word-for-word transcription"
        case .smart:
            return "Refine transcription with a custom prompt"
        }
    }
}
