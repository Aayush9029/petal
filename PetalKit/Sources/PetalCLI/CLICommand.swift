import Foundation

public enum CLICommand: Equatable, Sendable {
    case help
    case version
    case models(json: Bool)
    case transcribe(TranscribeOptions)
}

public struct TranscribeOptions: Equatable, Sendable {
    public enum Input: Equatable, Sendable {
        case file(String)
        case standardInput
    }

    public var input: Input
    public var modelID: String?
    public var outputPath: String?
    public var json: Bool

    public init(input: Input, modelID: String? = nil, outputPath: String? = nil, json: Bool = false) {
        self.input = input
        self.modelID = modelID
        self.outputPath = outputPath
        self.json = json
    }
}

public struct CLIUsageError: Error, Equatable, LocalizedError {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public extension CLICommand {
    static let subcommands: Set<String> = ["transcribe", "models", "help"]

    /// Finder and Xcode launch the app with flags such as `-NSDocumentRevisionsDebugMode`, so only these first arguments start the CLI.
    static func isInvocation(_ arguments: [String]) -> Bool {
        guard let first = arguments.first else { return false }
        return subcommands.contains(first) || ["-h", "--help", "--version"].contains(first)
    }

    static func parse(_ arguments: [String]) throws -> CLICommand {
        guard let first = arguments.first else { return .help }
        let rest = Array(arguments.dropFirst())
        switch first {
        case "help", "-h", "--help":
            return .help
        case "--version":
            return .version
        case "models":
            return try parseModels(rest)
        case "transcribe":
            return try parseTranscribe(rest)
        default:
            throw CLIUsageError("Unknown command '\(first)'.")
        }
    }

    private static func parseModels(_ arguments: [String]) throws -> CLICommand {
        var json = false
        for argument in arguments {
            switch argument {
            case "--json": json = true
            case "-h", "--help": return .help
            default: throw CLIUsageError("Unknown option '\(argument)' for 'models'.")
            }
        }
        return .models(json: json)
    }

    private static func parseTranscribe(_ arguments: [String]) throws -> CLICommand {
        var input: TranscribeOptions.Input?
        var modelID: String?
        var outputPath: String?
        var json = false
        var onlyPositionals = false
        var iterator = arguments.makeIterator()

        func value(for flag: String) throws -> String {
            guard let next = iterator.next(), !next.isEmpty else {
                throw CLIUsageError("Option '\(flag)' needs a value.")
            }
            return next
        }

        func setInput(_ newInput: TranscribeOptions.Input) throws {
            guard input == nil else { throw CLIUsageError("Give only one audio file.") }
            input = newInput
        }

        while let argument = iterator.next() {
            if onlyPositionals {
                try setInput(.file(argument))
                continue
            }
            switch argument {
            case "--":
                onlyPositionals = true
            case "-":
                try setInput(.standardInput)
            case "-m", "--model":
                modelID = try value(for: argument)
            case "-o", "--output":
                outputPath = try value(for: argument)
            case "--json":
                json = true
            case "-h", "--help":
                return .help
            default:
                if let inline = inlineValue(argument, flags: ["--model"]) {
                    modelID = inline
                } else if let inline = inlineValue(argument, flags: ["--output"]) {
                    outputPath = inline
                } else if argument.hasPrefix("-") {
                    throw CLIUsageError("Unknown option '\(argument)' for 'transcribe'.")
                } else {
                    try setInput(.file(argument))
                }
            }
        }

        guard let input else {
            throw CLIUsageError("Give an audio file, or '-' to read audio from standard input.")
        }
        return .transcribe(TranscribeOptions(input: input, modelID: modelID, outputPath: outputPath, json: json))
    }

    private static func inlineValue(_ argument: String, flags: [String]) -> String? {
        for flag in flags where argument.hasPrefix(flag + "=") {
            return String(argument.dropFirst(flag.count + 1))
        }
        return nil
    }
}

public enum CLIHelp {
    public static let text = """
    Transcribe audio files on this Mac with the speech models that Petal downloaded.

    Usage:
      petal transcribe <file | -> [options]
      petal models [--json]
      petal --version

    Transcribe options:
      -m, --model <id>     Use this model. Default: the model selected in Petal.
      -o, --output <path>  Write the transcript to a file. Default: standard output.
          --json           Print JSON with the model, the audio duration, and the text.
      -                    Read the audio from standard input.

    Examples:
      petal transcribe meeting.m4a
      petal transcribe memo.wav -m whisper-large-v3-turbo -o memo.txt
      curl -s https://example.com/clip.mp3 | petal transcribe - --json | jq -r .text

    Exit codes: 0 success, 1 failure, 2 usage error, 130 interrupted, 143 terminated.
    """
}
