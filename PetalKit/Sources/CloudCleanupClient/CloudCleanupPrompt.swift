import Foundation
import Shared

enum CloudCleanupPrompt {
    struct FunctionTool: Equatable {
        var name: String
        var description: String
    }

    static let maxToolTextLength = 8_000

    static func functionTools(for tools: Set<CloudTool>) -> [FunctionTool] {
        CloudTool.allCases.filter(tools.contains).compactMap { tool in
            tool.functionName.map { FunctionTool(name: $0, description: description(of: tool)) }
        }
    }

    static func description(of tool: CloudTool) -> String {
        switch tool {
        case .dateTime: "Returns the speaker's current local date, weekday, time, and time zone."
        case .clipboard: "Returns the text that the speaker copied to the clipboard."
        case .selectedText: "Returns the text that the speaker selected in their current app."
        case .webSearch: "Searches the web."
        }
    }

    static func instructions(for tool: CloudTool) -> String {
        switch tool {
        case .dateTime:
            """
            You can call get_current_date_time to get the speaker's current date, time, and time zone. Call it before you write an exact date or time. When the text has a relative date or time (today, tomorrow, next Friday, in two hours), call it and add the exact date, for example "next Friday (October 9)".
            """
        case .webSearch:
            """
            You can search the web. Search only when the speaker asks you to look something up or leaves a fact for you to fill in. Write what you find as plain words. Add a URL only when the speaker asks for a link, and never add citation markers.
            """
        case .clipboard:
            """
            You can call get_clipboard_text to read the text the speaker copied. Call it only when the speaker refers to copied text, such as "this" or "what I copied".
            """
        case .selectedText:
            """
            You can call get_selected_text to read the text the speaker selected in their current app. Call it when the speaker refers to the selection, such as "reply to this" or "make this shorter". Your reply replaces the selected text.
            """
        }
    }

    static func system(_ prompt: String, tools: Set<CloudTool>, variables: [CloudPromptVariable: String]) -> String {
        let sections = [render(prompt, variables: variables).trimmingCharacters(in: .whitespacesAndNewlines)]
            + CloudTool.allCases.filter(tools.contains).map(instructions(for:))
        return sections.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func render(_ prompt: String, variables: [CloudPromptVariable: String]) -> String {
        CloudPromptVariable.allCases.reduce(prompt) { text, variable in
            text.replacingOccurrences(of: variable.token, with: variables[variable] ?? "")
        }
    }

    static func variables(
        now: Date,
        timeZone: TimeZone,
        locale: Locale,
        appName: String?,
        userName: String
    ) -> [CloudPromptVariable: String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = Date.FormatStyle(date: .complete, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone)
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone)
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        return [
            .date: now.formatted(date),
            .time: now.formatted(time),
            .timeZone: timeZone.identifier,
            .app: appName ?? "the current app",
            .name: userName.isEmpty ? "the speaker" : userName,
            .language: Locale(identifier: "en").localizedString(forLanguageCode: languageCode) ?? "English",
        ]
    }

    /// Without the tags, chat models answer questions in the transcript instead of cleaning them.
    static func user(_ transcript: String) -> String {
        "<transcript>\n\(transcript.trimmingCharacters(in: .whitespacesAndNewlines))\n</transcript>"
    }

    static let emptyParameters: JSONValue = [
        "type": "object",
        "properties": [:],
        "required": [],
        "additionalProperties": false,
    ]

    static func dateTimeToolOutput(now: Date, timeZone: TimeZone) -> String {
        func format(_ pattern: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = pattern
            return formatter.string(from: now)
        }
        let output: JSONValue = [
            "date": .string(format("yyyy-MM-dd")),
            "weekday": .string(format("EEEE")),
            "time": .string(format("HH:mm")),
            "time_zone": .string(timeZone.identifier),
            "utc_offset": .string(format("xxx")),
        ]
        return output.encodedString()
    }

    static func textToolOutput(_ text: String?, emptyMessage: String) -> String {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return (["text": nil, "note": .string(emptyMessage)] as JSONValue).encodedString()
        }
        return (["text": .string(String(text.prefix(maxToolTextLength)))] as JSONValue).encodedString()
    }
}
