import CustomDump
import Foundation
import Shared
import Testing
@testable import CloudCleanupClient
@testable import CloudCleanupFeature

@Suite
struct CloudCleanupRequestTests {
    @Test
    func openAIRequestUsesResponsesFormatWithTools() throws {
        let configuration = Fixtures.configuration(.openAI, model: "gpt-6-luna", tools: [.dateTime, .webSearch])
        let request = try OpenAIResponsesAPI(configuration: configuration, system: "System.", transcript: "um hi").request()

        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.timeoutInterval == 60)
        expectNoDifference(try Fixtures.body(request), [
            "model": "gpt-6-luna",
            "store": false,
            "instructions": "System.",
            "input": [["role": "user", "content": "<transcript>\num hi\n</transcript>"]],
            "reasoning": ["effort": "none"],
            "include": ["reasoning.encrypted_content"],
            "tools": [
                [
                    "type": "function",
                    "name": "get_current_date_time",
                    "description": .string(CloudCleanupPrompt.description(of: .dateTime)),
                    "parameters": CloudCleanupPrompt.emptyParameters,
                    "strict": true,
                ],
                ["type": "web_search"],
            ],
        ])
    }

    @Test(arguments: [
        ("gpt-6-luna", "none"),
        ("gpt-6-sol", "none"),
        ("gpt-6.1-sol", "low"),
        ("gpt-6-astra", "low"),
        ("gpt-5-mini", "minimal"),
        ("gpt-5-mini-2025-08-07", "minimal"),
        ("gpt-5.4-mini", "none"),
        ("o4-mini", "low"),
    ])
    func openAIReasoningEffortMatchesModelFamily(model: String, effort: String) {
        #expect(OpenAIResponsesAPI.reasoningEffort(for: CloudModel.ID(rawValue: model)) == effort)
    }

    @Test
    func openAIRequestWithoutReasoningOmitsEffort() throws {
        let request = try OpenAIResponsesAPI(configuration: Fixtures.configuration(.openAI, model: "gpt-4.1"), system: "System.", transcript: "hi").request()
        let body = try Fixtures.body(request)
        #expect(body["reasoning"] == nil)
        #expect(body["include"] == nil)
        #expect(body["tools"] == nil)
        #expect(request.timeoutInterval == 30)
    }

    @Test
    func anthropicRequestAddsEffortFallbacksAndCurrentSearchTool() throws {
        let configuration = Fixtures.configuration(.anthropic, model: "claude-opus-5-5", tools: [.dateTime, .webSearch])
        let request = try AnthropicMessagesAPI(configuration: configuration, system: "System.", transcript: "um hi").request()

        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        expectNoDifference(try Fixtures.body(request), [
            "model": "claude-opus-5-5",
            "max_tokens": 16000,
            "system": "System.",
            "messages": [["role": "user", "content": "<transcript>\num hi\n</transcript>"]],
            "output_config": ["effort": "low"],
            "fallbacks": "default",
            "tools": [
                [
                    "name": "get_current_date_time",
                    "description": .string(CloudCleanupPrompt.description(of: .dateTime)),
                    "input_schema": CloudCleanupPrompt.emptyParameters,
                    "strict": true,
                ],
                ["type": "web_search_20260209", "name": "web_search", "max_uses": 3],
            ],
        ])
    }

    @Test
    func anthropicHaikuSkipsEffortAndFallbacks() throws {
        let configuration = Fixtures.configuration(.anthropic, model: "claude-haiku-4-5", tools: [.webSearch])
        let request = try AnthropicMessagesAPI(configuration: configuration, system: "System.", transcript: "hi").request()
        let body = try Fixtures.body(request)

        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
        #expect(body["output_config"] == nil)
        #expect(body["fallbacks"] == nil)
        expectNoDifference(body["tools"], [["type": "web_search_20250305", "name": "web_search", "max_uses": 3]])
    }

    @Test(arguments: [
        ("claude-opus-5-5", true),
        ("claude-sonnet-5-5", true),
        ("claude-opus-4-6", true),
        ("claude-sonnet-4-6", true),
        ("claude-fable-5-1", true),
        ("claude-opus-4-5", false),
        ("claude-opus-4-5-20251101", false),
        ("claude-sonnet-4-20250514", false),
        ("claude-haiku-4-5", false),
        ("claude-3-7-sonnet-latest", false),
    ])
    func anthropicGenerationDetection(model: String, isCurrent: Bool) {
        #expect(AnthropicMessagesAPI.isCurrentGeneration(CloudModel.ID(rawValue: model)) == isCurrent)
    }

    @Test
    func openRouterRequestUsesChatCompletionsWithServerSearch() throws {
        let configuration = Fixtures.configuration(.openRouter, model: "anthropic/claude-sonnet-5.5", tools: [.dateTime, .webSearch])
        let request = try ChatCompletionsAPI(configuration: configuration, system: "System.", transcript: "um hi").request()

        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "X-Title") == "Petal")
        expectNoDifference(try Fixtures.body(request), [
            "model": "anthropic/claude-sonnet-5.5",
            "stream": false,
            "messages": [
                ["role": "system", "content": "System."],
                ["role": "user", "content": "<transcript>\num hi\n</transcript>"],
            ],
            "reasoning": ["effort": "low", "exclude": true],
            "tools": [
                [
                    "type": "function",
                    "function": [
                        "name": "get_current_date_time",
                        "description": .string(CloudCleanupPrompt.description(of: .dateTime)),
                        "parameters": CloudCleanupPrompt.emptyParameters,
                    ],
                ],
                ["type": "openrouter:web_search", "parameters": ["max_results": 5]],
            ],
        ])
    }

    @Test(arguments: [
        ("openai/gpt-6-luna", ["effort": "none"]),
        ("qwen/qwen3.8-flash", ["enabled": false]),
        ("deepseek/deepseek-v4.1-flash", ["enabled": false]),
        ("google/gemini-3.8-flash", ["effort": "low", "exclude": true]),
    ] as [(String, JSONValue)])
    func openRouterReasoningMatchesModelFamily(model: String, reasoning: JSONValue) {
        expectNoDifference(ChatCompletionsAPI.openRouterReasoning(for: CloudModel.ID(rawValue: model)), reasoning)
    }

    @Test
    func customServerSkipsReasoningWebSearchAndEmptyKey() throws {
        var configuration = Fixtures.configuration(.custom, model: "llama3.2", tools: [.dateTime, .webSearch])
        configuration.connection = CloudConnection(provider: .custom, baseURL: "localhost:11434/v1/")
        let request = try ChatCompletionsAPI(configuration: configuration, system: "System.", transcript: "hi").request()
        let body = try Fixtures.body(request)

        #expect(request.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(body["reasoning"] == nil)
        #expect(body["tools"]?.arrayValue?.count == 1)
    }

    @Test(arguments: [
        ("http://localhost:11434/v1", "http://localhost:11434/v1"),
        ("localhost:1234/v1/", "http://localhost:1234/v1"),
        ("https://api.groq.com/openai/v1/chat/completions", "https://api.groq.com/openai/v1"),
        ("  http://127.0.0.1:8080/v1//  ", "http://127.0.0.1:8080/v1"),
    ])
    func customBaseURLAcceptsCommonForms(input: String, expected: String) throws {
        #expect(try CloudConnection(provider: .custom, baseURL: input).customBaseURL().absoluteString == expected)
    }

    @Test
    func customBaseURLRejectsEmptyText() {
        #expect(throws: CloudCleanupError.invalidBaseURL) {
            try CloudConnection(provider: .custom, baseURL: "  ").customBaseURL()
        }
    }

    @Test
    func missingKeyFailsBeforeAnyRequest() {
        var configuration = Fixtures.configuration(.openRouter, model: "openai/gpt-6-luna")
        configuration.connection.apiKey = ""
        #expect(throws: CloudCleanupError.missingAPIKey(.openRouter)) {
            try ChatCompletionsAPI(configuration: configuration, system: "System.", transcript: "hi").request()
        }
    }

    @Test
    func openAIRequestSendsTheScreenshotBeforeTheTranscript() throws {
        let configuration = Fixtures.configuration(.openAI, model: "gpt-6-luna", tools: [.screen])
        let body = try Fixtures.body(
            OpenAIResponsesAPI(configuration: configuration, system: "System.", transcript: "hi", screenshot: Fixtures.screenshot).request()
        )

        expectNoDifference(body["input"], [
            [
                "role": "user",
                "content": [
                    ["type": "input_image", "image_url": "data:image/jpeg;base64,/9j/", "detail": "auto"],
                    ["type": "input_text", "text": "<transcript>\nhi\n</transcript>"],
                ],
            ],
        ])
        #expect(body["tools"] == nil)
    }

    @Test
    func anthropicRequestSendsTheScreenshotAsABase64ImageBlock() throws {
        let configuration = Fixtures.configuration(.anthropic, model: "claude-opus-5-5", tools: [.screen])
        let body = try Fixtures.body(
            AnthropicMessagesAPI(configuration: configuration, system: "System.", transcript: "hi", screenshot: Fixtures.screenshot).request()
        )

        expectNoDifference(body["messages"], [
            [
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": "/9j/"]],
                    ["type": "text", "text": "<transcript>\nhi\n</transcript>"],
                ],
            ],
        ])
        #expect(body["tools"] == nil)
    }

    @Test
    func chatCompletionsRequestSendsTheScreenshotAsAnImageURLPart() throws {
        let configuration = Fixtures.configuration(.openRouter, model: "google/gemini-3.8-flash", tools: [.screen])
        let body = try Fixtures.body(
            ChatCompletionsAPI(configuration: configuration, system: "System.", transcript: "hi", screenshot: Fixtures.screenshot).request()
        )

        expectNoDifference(body["messages"], [
            ["role": "system", "content": "System."],
            [
                "role": "user",
                "content": [
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,/9j/"]],
                    ["type": "text", "text": "<transcript>\nhi\n</transcript>"],
                ],
            ],
        ])
        #expect(body["tools"] == nil)
    }

    @Test(arguments: CloudProvider.allCases)
    func requestsWithoutAScreenshotSendOnlyTheTranscript(provider: CloudProvider) throws {
        var configuration = Fixtures.configuration(provider, model: "model", tools: [.screen])
        configuration.connection.baseURL = "localhost:11434/v1"
        let body = try Fixtures.body(CloudCleanupRuntime.api(for: configuration, system: "System.", transcript: "hi").request())

        expectNoDifference(Fixtures.userMessage(in: body), ["role": "user", "content": "<transcript>\nhi\n</transcript>"])
    }

    @Test(arguments: [CloudProvider.openAI, .anthropic, .openRouter])
    func aRejectedScreenshotIsDroppedOnce(provider: CloudProvider) throws {
        let configuration = Fixtures.configuration(provider, model: "model", tools: [.screen])
        var api = CloudCleanupRuntime.api(for: configuration, system: "System.", transcript: "hi", screenshot: Fixtures.screenshot)

        let retries = [
            api.adapt(to: .http(status: 400, message: "max_tokens: too large")),
            api.adapt(to: .http(status: 500, message: "Image service is down.")),
            api.adapt(to: .http(status: 400, message: "This model does not support image input.")),
            api.adapt(to: .http(status: 400, message: "This model does not support image input.")),
        ]

        #expect(retries == [false, false, true, false])
        expectNoDifference(
            Fixtures.userMessage(in: try Fixtures.body(api.request())),
            ["role": "user", "content": "<transcript>\nhi\n</transcript>"]
        )
    }
}

@Suite
struct CloudCleanupResponseTests {
    @Test
    func openAIPrefersFinalAnswerOverCommentary() throws {
        var api = OpenAIResponsesAPI(configuration: Fixtures.configuration(.openAI, model: "gpt-6-luna"), system: "System.", transcript: "hi")
        let turn = try api.receive([
            "model": "gpt-6-luna",
            "output": [
                ["type": "message", "phase": "commentary", "content": [["type": "output_text", "text": "Checking."]]],
                ["type": "message", "phase": "final_answer", "content": [["type": "output_text", "text": "Hi."]]],
            ],
        ])
        expectNoDifference(turn, .finished(text: "Hi.", model: "gpt-6-luna"))
        #expect(api.input.count == 3)
    }

    @Test
    func openAIErrorBodyThrows() {
        var api = OpenAIResponsesAPI(configuration: Fixtures.configuration(.openAI, model: "gpt-6-luna"), system: "System.", transcript: "hi")
        #expect(throws: CloudCleanupError.provider("Model not found.")) {
            try api.receive(["error": ["message": "Model not found."]])
        }
    }

    @Test
    func anthropicFinalTextSkipsTextBeforeTheLastSearch() {
        let text = AnthropicMessagesAPI.finalText([
            ["type": "thinking", "thinking": ""],
            ["type": "text", "text": "Let me look that up."],
            ["type": "server_tool_use", "id": "srvtoolu_1", "name": "web_search"],
            ["type": "web_search_tool_result", "tool_use_id": "srvtoolu_1", "content": []],
            ["type": "text", "text": "Sam, OpenAI's CEO is "],
            ["type": "text", "text": "Sam Altman.", "citations": []],
        ])
        #expect(text == "Sam, OpenAI's CEO is Sam Altman.")
    }

    @Test
    func anthropicRefusalThrows() {
        var api = AnthropicMessagesAPI(configuration: Fixtures.configuration(.anthropic, model: "claude-opus-5-5"), system: "System.", transcript: "hi")
        #expect(throws: CloudCleanupError.refused) {
            try api.receive(["type": "message", "stop_reason": "refusal", "content": []])
        }
    }

    @Test
    func chatCompletionsReadsContentParts() {
        #expect(ChatCompletionsAPI.text(of: [["type": "text", "text": "Hi "], ["type": "text", "text": "there."]]) == "Hi there.")
        #expect(ChatCompletionsAPI.text(of: "Hi.") == "Hi.")
        #expect(ChatCompletionsAPI.text(of: nil) == "")
    }

    @Test
    func openRouterModelListKeepsTextModelsWithNames() {
        let models = CloudModelCatalog.models(
            from: ["data": [
                ["id": "openai/gpt-6-luna", "name": "OpenAI: GPT-6 Luna", "architecture": ["output_modalities": ["text"]]],
                ["id": "google/gemini-3.1-flash-image", "name": "Image", "architecture": ["output_modalities": ["image"]]],
                ["id": "anthropic/claude-sonnet-5.5", "name": "Anthropic: Claude Sonnet 5.5"],
                ["id": "anthropic/claude-sonnet-5.5:batch", "name": "Anthropic: Claude Sonnet 5.5 (batch)"],
            ]],
            provider: .openRouter
        )
        expectNoDifference(models, [
            CloudModel(id: "openai/gpt-6-luna", name: "OpenAI: GPT-6 Luna"),
            CloudModel(id: "anthropic/claude-sonnet-5.5", name: "Anthropic: Claude Sonnet 5.5"),
        ])
    }

    @Test
    func anthropicModelListUsesDisplayNames() {
        let models = CloudModelCatalog.models(
            from: ["data": [["id": "claude-opus-5-5", "display_name": "Claude Opus 5.5"]]],
            provider: .anthropic
        )
        expectNoDifference(models, [CloudModel(id: "claude-opus-5-5", name: "Claude Opus 5.5")])
    }

    @Test
    func openRouterListsModelsWithoutAKeyButChecksKeysOnItsKeyEndpoint() throws {
        let anonymous = CloudConnection(provider: .openRouter)
        let list = try CloudModelCatalog.listRequest(for: anonymous)
        #expect(list.url?.absoluteString == "https://openrouter.ai/api/v1/models")
        #expect(list.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(throws: CloudCleanupError.missingAPIKey(.openRouter)) {
            try CloudModelCatalog.keyCheckRequest(for: anonymous)
        }
        let check = try CloudModelCatalog.keyCheckRequest(for: CloudConnection(provider: .openRouter, apiKey: "sk-or-test"))
        #expect(check.url?.absoluteString == "https://openrouter.ai/api/v1/key")
        #expect(check.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-test")
    }

    @Test
    func openAIModelListKeepsChatModelsNewestFirst() {
        let models = CloudModelCatalog.models(
            from: ["data": [
                ["id": "gpt-5.4-mini", "created": 100],
                ["id": "gpt-6-luna", "created": 300],
                ["id": "text-embedding-3-large", "created": 400],
                ["id": "gpt-realtime", "created": 500],
                ["id": "o4-mini", "created": 200],
            ]],
            provider: .openAI
        )
        expectNoDifference(models, [CloudModel(id: "gpt-6-luna"), CloudModel(id: "o4-mini"), CloudModel(id: "gpt-5.4-mini")])
    }
}

@Suite
struct CloudCleanupPromptTests {
    @Test
    func systemPromptAppendsToolGuidanceForEnabledTools() {
        #expect(CloudCleanupPrompt.system("  Clean the <transcript>.\n", tools: [], variables: [:]) == "Clean the <transcript>.")
        #expect(
            CloudCleanupPrompt.system("Clean the <transcript>.", tools: [.webSearch], variables: [:])
                == "Clean the <transcript>.\n\n\(CloudCleanupPrompt.instructions(for: .webSearch))"
        )
        #expect(
            CloudCleanupPrompt.system("Clean the <transcript>.", tools: [.selectedText, .dateTime, .clipboard], variables: [:])
                == [
                    "Clean the <transcript>.",
                    CloudCleanupPrompt.instructions(for: .dateTime),
                    CloudCleanupPrompt.instructions(for: .clipboard),
                    CloudCleanupPrompt.instructions(for: .selectedText),
                ].joined(separator: "\n\n")
        )
    }

    @Test
    func screenToolAddsGuidanceButNoFunction() {
        #expect(CloudTool.screen.functionName == nil)
        #expect(CloudCleanupPrompt.functionTools(for: [.screen, .dateTime]).map(\.name) == ["get_current_date_time"])
        #expect(
            CloudCleanupPrompt.system("Clean the <transcript>.", tools: [.screen], variables: [:])
                == "Clean the <transcript>.\n\n\(CloudCleanupPrompt.instructions(for: .screen))"
        )
    }

    @Test
    func variablesFillTheirTokens() throws {
        let variables = CloudCleanupPrompt.variables(
            timeZone: try #require(TimeZone(identifier: "America/New_York")),
            locale: Locale(identifier: "en_US"),
            appName: "Slack",
            windowTitle: "#launch",
            userName: "Alex Kim"
        )
        expectNoDifference(
            CloudCleanupPrompt.render(
                "{{name}} ({{first_name}}) writes in {{app}}, {{window}}, in {{language}} from the {{region}} ({{time_zone}}). {{date}}",
                variables: variables
            ),
            "Alex Kim (Alex) writes in Slack, #launch, in English from the United States (America/New_York). {{date}}"
        )
    }

    @Test
    func missingContextUsesNeutralWords() {
        let variables = CloudCleanupPrompt.variables(timeZone: .gmt, locale: Locale(identifier: "es_MX"), appName: nil, windowTitle: nil, userName: "")
        #expect(variables[.app] == "the current app")
        #expect(variables[.window] == "the current window")
        #expect(variables[.name] == "the speaker")
        #expect(variables[.firstName] == "the speaker")
        #expect(variables[.language] == "Spanish")
        #expect(variables[.region] == "Mexico")
    }

    @Test
    func aPromptWithoutTheTranscriptTagGetsTheTranscriptSentence() {
        #expect(CloudCleanupPrompt.system("Fix my words.", tools: [], variables: [:]) == "Fix my words.\n\n\(CloudPromptTranscript.sentence)")
        #expect(CloudCleanupPrompt.system("", tools: [], variables: [:]) == CloudPromptTranscript.sentence)
        #expect(CloudCleanupPrompt.system("Fix the <transcript>.", tools: [], variables: [:]) == "Fix the <transcript>.")
    }

    @Test
    func textToolOutputTruncatesAndExplainsEmptyText() throws {
        expectNoDifference(
            try JSONValue.decode(Data(CloudCleanupPrompt.textToolOutput("  ", emptyMessage: "No text is selected.").utf8)),
            ["text": nil, "note": "No text is selected."]
        )
        let long = String(repeating: "a", count: CloudCleanupPrompt.maxToolTextLength + 10)
        let output = try JSONValue.decode(Data(CloudCleanupPrompt.textToolOutput(long, emptyMessage: "").utf8))
        #expect(output["text"]?.stringValue?.count == CloudCleanupPrompt.maxToolTextLength)
    }

    @Test
    func dateTimeToolReportsLocalDateAndZone() throws {
        let output = CloudCleanupPrompt.dateTimeToolOutput(
            now: Date(timeIntervalSince1970: 1_791_056_340),
            timeZone: try #require(TimeZone(identifier: "America/New_York"))
        )
        expectNoDifference(try JSONValue.decode(Data(output.utf8)), [
            "date": "2026-10-03",
            "weekday": "Saturday",
            "time": "15:39",
            "time_zone": "America/New_York",
            "utc_offset": "-04:00",
        ])
    }

    @Test
    func presetsAreDistinctAndMatchTheirOwnText() {
        for preset in CloudPromptPreset.allCases {
            #expect(CloudPromptPreset.matching(preset.prompt) == preset)
        }
        #expect(CloudPromptPreset.matching("Custom prompt") == nil)
    }

    @Test(arguments: [
        ("Sam's CEO is Sam Altman. ([openai.com](https://openai.com/our-structure/?utm_source=openai))", "Sam's CEO is Sam Altman."),
        ("Launch is Tuesday [theverge.com](https://www.theverge.com/a) and more.", "Launch is Tuesday and more."),
        ("Read [the guide](https://example.com/guide).", "Read [the guide](https://example.com/guide)."),
        ("Thanks,  \nAlex  ", "Thanks,\nAlex"),
        ("<transcript>\nHi there.\n</transcript>", "Hi there."),
        ("  - Eggs\n  - Milk", "- Eggs\n  - Milk"),
    ])
    func sanitizerRemovesChatOnlyMarkup(input: String, expected: String) {
        #expect(CloudOutputSanitizer.clean(input) == expected)
    }
}

@Suite
struct CloudCleanupRuntimeTests {
    @Test
    func openAIDateToolLoopSendsTheLocalDateBack() async throws {
        let transport = FakeTransport([
            (200, ["model": "gpt-6-luna", "output": [
                ["id": "fc_1", "type": "function_call", "call_id": "call_1", "name": "get_current_date_time", "arguments": "{}"],
            ]]),
            (200, ["model": "gpt-6-luna", "output": [
                ["type": "message", "content": [["type": "output_text", "text": "Call Mom next Friday (October 9)."]]],
            ]]),
        ])
        let runtime = CloudCleanupRuntime(
            send: transport.send,
            context: CloudRuntimeContext(
                now: { Date(timeIntervalSince1970: 1_791_056_340) },
                timeZone: TimeZone(identifier: "America/New_York")!
            )
        )

        let result = try await runtime.clean(
            "call mom next friday",
            configuration: Fixtures.configuration(.openAI, model: "gpt-6-luna", tools: [.dateTime])
        )

        expectNoDifference(result, CloudCleanupResult(
            text: "Call Mom next Friday (October 9).",
            model: "gpt-6-luna",
            toolCalls: ["get_current_date_time"],
            requestCount: 2
        ))
        let followUp = try Fixtures.body(transport.requests.value[1])
        expectNoDifference(followUp["input"]?.arrayValue?.last, [
            "type": "function_call_output",
            "call_id": "call_1",
            "output": .string(CloudCleanupPrompt.dateTimeToolOutput(
                now: Date(timeIntervalSince1970: 1_791_056_340),
                timeZone: TimeZone(identifier: "America/New_York")!
            )),
        ])
        #expect(followUp["input"]?.arrayValue?.count == 3)
    }

    @Test
    func clipboardAndSelectionToolsReturnTheirText() async throws {
        let transport = FakeTransport([
            (200, ["output": [
                ["type": "function_call", "call_id": "call_1", "name": "get_clipboard_text", "arguments": "{}"],
                ["type": "function_call", "call_id": "call_2", "name": "get_selected_text", "arguments": "{}"],
            ]]),
            (200, ["output": [["type": "message", "content": [["type": "output_text", "text": "Done."]]]]]),
        ])
        let runtime = CloudCleanupRuntime(
            send: transport.send,
            context: CloudRuntimeContext(
                timeZone: .gmt,
                clipboardText: { "Launch moved to Tuesday." },
                selectedText: { nil }
            )
        )

        let result = try await runtime.clean(
            "reply to this",
            configuration: Fixtures.configuration(.openAI, model: "gpt-6-luna", tools: [.clipboard, .selectedText])
        )

        expectNoDifference(result.toolCalls, ["get_clipboard_text", "get_selected_text"])
        let outputs = try Fixtures.body(transport.requests.value[1])["input"]?.arrayValue?.suffix(2).compactMap { $0["output"]?.stringValue }
        expectNoDifference(outputs, [
            #"{"text":"Launch moved to Tuesday."}"#,
            #"{"note":"No text is selected.","text":null}"#,
        ])
    }

    @Test
    func systemPromptGetsTheSpeakerContext() async throws {
        let transport = FakeTransport([(200, ["output": [["type": "message", "content": [["type": "output_text", "text": "Hi."]]]]])])
        let runtime = CloudCleanupRuntime(
            send: transport.send,
            context: CloudRuntimeContext(timeZone: .gmt, appName: { "Mail" }, userName: { "Alex Kim" })
        )
        var configuration = Fixtures.configuration(.openAI, model: "gpt-6-luna")
        configuration.systemPrompt = "Write the <transcript> for {{app}} as {{name}}."

        _ = try await runtime.clean("hi", configuration: configuration)

        #expect(try Fixtures.body(transport.requests.value[0])["instructions"] == "Write the <transcript> for Mail as Alex Kim.")
    }

    @Test
    func contextIsReadOnlyForVariablesThePromptUses() async throws {
        let transport = FakeTransport([(200, ["output": [["type": "message", "content": [["type": "output_text", "text": "Hi."]]]]])])
        let runtime = CloudCleanupRuntime(
            send: transport.send,
            context: CloudRuntimeContext(
                timeZone: .gmt,
                appName: {
                    Issue.record("Read the app name for a prompt without {{app}}")
                    return "Mail"
                },
                windowTitle: { "Re: Launch" }
            )
        )
        var configuration = Fixtures.configuration(.openAI, model: "gpt-6-luna")
        configuration.systemPrompt = "Reply to {{window}} with the <transcript>."

        _ = try await runtime.clean("hi", configuration: configuration)

        #expect(try Fixtures.body(transport.requests.value[0])["instructions"] == "Reply to Re: Launch with the <transcript>.")
    }

    @Test
    func anthropicPausedSearchResumesWithTheSameAssistantTurn() async throws {
        let pausedContent: JSONValue = [["type": "server_tool_use", "id": "srvtoolu_1", "name": "web_search", "input": ["query": "x"]]]
        let transport = FakeTransport([
            (200, ["type": "message", "stop_reason": "pause_turn", "content": pausedContent]),
            (200, ["type": "message", "model": "claude-opus-5-5", "stop_reason": "end_turn", "content": [["type": "text", "text": "Done."]]]),
        ])
        let runtime = CloudCleanupRuntime(send: transport.send, context: CloudRuntimeContext(timeZone: .gmt))

        let result = try await runtime.clean(
            "look it up",
            configuration: Fixtures.configuration(.anthropic, model: "claude-opus-5-5", tools: [.webSearch])
        )

        #expect(result.text == "Done.")
        #expect(result.requestCount == 2)
        let resumed = try Fixtures.body(transport.requests.value[1])
        expectNoDifference(resumed["messages"]?.arrayValue?.last, ["role": "assistant", "content": pausedContent])
    }

    @Test
    func anthropicRetriesWithoutFallbacksWhenTheBetaIsRejected() async throws {
        let transport = FakeTransport([
            (400, ["type": "error", "error": ["type": "invalid_request_error", "message": "fallbacks: Extra inputs are not permitted"]]),
            (200, ["type": "message", "stop_reason": "end_turn", "content": [["type": "text", "text": "Hi."]]]),
        ])
        let runtime = CloudCleanupRuntime(send: transport.send, context: CloudRuntimeContext(timeZone: .gmt))

        let result = try await runtime.clean("hi", configuration: Fixtures.configuration(.anthropic, model: "claude-opus-5-5"))

        #expect(result.text == "Hi.")
        let retry = transport.requests.value[1]
        #expect(try Fixtures.body(retry)["fallbacks"] == nil)
        #expect(retry.value(forHTTPHeaderField: "anthropic-beta") == nil)
    }

    @Test
    func otherBadRequestsAreNotRetried() async {
        let transport = FakeTransport([(400, ["type": "error", "error": ["message": "max_tokens: too large"]])])
        let runtime = CloudCleanupRuntime(send: transport.send, context: CloudRuntimeContext(timeZone: .gmt))

        await #expect(throws: CloudCleanupError.http(status: 400, message: "max_tokens: too large")) {
            try await runtime.clean("hi", configuration: Fixtures.configuration(.anthropic, model: "claude-opus-5-5"))
        }
        #expect(transport.requests.value.count == 1)
    }

    @Test
    func chatCompletionsToolLoopAppendsToolMessages() async throws {
        let transport = FakeTransport([
            (200, ["choices": [["message": [
                "role": "assistant",
                "content": nil,
                "tool_calls": [["id": "call_9", "type": "function", "function": ["name": "get_current_date_time", "arguments": "{}"]]],
            ]]]]),
            (200, ["model": "openai/gpt-6-luna", "choices": [["message": ["role": "assistant", "content": "Today is Saturday."]]]]),
        ])
        let runtime = CloudCleanupRuntime(send: transport.send, context: CloudRuntimeContext(timeZone: .gmt))

        let result = try await runtime.clean(
            "what day is it",
            configuration: Fixtures.configuration(.openRouter, model: "openai/gpt-6-luna", tools: [.dateTime])
        )

        #expect(result.text == "Today is Saturday.")
        let messages = try #require(try Fixtures.body(transport.requests.value[1])["messages"]?.arrayValue)
        #expect(messages.count == 4)
        #expect(messages[2]["tool_calls"]?.arrayValue?.count == 1)
        #expect(messages[3]["role"] == "tool")
        #expect(messages[3]["tool_call_id"] == "call_9")
    }

    @Test
    func screenToolSendsTheScreenshotWithItsGuidance() async throws {
        let transport = FakeTransport([(200, ["type": "message", "stop_reason": "end_turn", "content": [["type": "text", "text": "Hi."]]])])
        let runtime = CloudCleanupRuntime(
            send: transport.send,
            context: CloudRuntimeContext(timeZone: .gmt, screenshot: { Fixtures.screenshot })
        )

        _ = try await runtime.clean("hi", configuration: Fixtures.configuration(.anthropic, model: "claude-opus-5-5", tools: [.screen]))

        let body = try Fixtures.body(transport.requests.value[0])
        #expect(body["system"] == .string("Clean the <transcript>.\n\n\(CloudCleanupPrompt.instructions(for: .screen))"))
        #expect(body["messages"]?[0]?["content"]?[0]?["type"] == "image")
    }

    @Test
    func screenToolWithoutACaptureSendsOnlyTheTranscript() async throws {
        let transport = FakeTransport([(200, ["type": "message", "stop_reason": "end_turn", "content": [["type": "text", "text": "Hi."]]])])
        let runtime = CloudCleanupRuntime(send: transport.send, context: CloudRuntimeContext(timeZone: .gmt))

        _ = try await runtime.clean("hi", configuration: Fixtures.configuration(.anthropic, model: "claude-opus-5-5", tools: [.screen]))

        let body = try Fixtures.body(transport.requests.value[0])
        #expect(body["system"] == "Clean the <transcript>.")
        expectNoDifference(body["messages"], [["role": "user", "content": "<transcript>\nhi\n</transcript>"]])
    }

    @Test
    func screenIsCapturedOnlyWhenTheToolIsOn() async throws {
        let captures = LockIsolated(0)
        let transport = FakeTransport([(200, ["choices": [["message": ["role": "assistant", "content": "Hi."]]]])])
        let runtime = CloudCleanupRuntime(
            send: transport.send,
            context: CloudRuntimeContext(timeZone: .gmt, screenshot: {
                captures.withValue { $0 += 1 }
                return Fixtures.screenshot
            })
        )

        _ = try await runtime.clean("hi", configuration: Fixtures.configuration(.openRouter, model: "openai/gpt-6-luna", tools: [.dateTime]))

        #expect(captures.value == 0)
        #expect(try Fixtures.body(transport.requests.value[0])["messages"]?[1]?["content"] == "<transcript>\nhi\n</transcript>")
    }

    @Test
    func aModelThatCannotReadImagesGetsTheTranscriptWithoutTheScreenshot() async throws {
        let transport = FakeTransport([
            (404, ["error": ["message": "No endpoints found that support image input"]]),
            (200, ["model": "deepseek/deepseek-v4.1-flash", "choices": [["message": ["role": "assistant", "content": "Hi."]]]]),
        ])
        let runtime = CloudCleanupRuntime(
            send: transport.send,
            context: CloudRuntimeContext(timeZone: .gmt, screenshot: { Fixtures.screenshot })
        )

        let result = try await runtime.clean(
            "hi",
            configuration: Fixtures.configuration(.openRouter, model: "deepseek/deepseek-v4.1-flash", tools: [.screen])
        )

        #expect(result.text == "Hi.")
        #expect(result.requestCount == 2)
        expectNoDifference(
            try Fixtures.body(transport.requests.value[1])["messages"]?[1],
            ["role": "user", "content": "<transcript>\nhi\n</transcript>"]
        )
    }

    @Test
    func modelCheckSendsATinyRequestWithoutTools() async throws {
        let transport = FakeTransport([(200, ["model": "gpt-6-luna", "output": []])])
        let runtime = CloudCleanupRuntime(send: transport.send, context: CloudRuntimeContext(timeZone: .gmt))

        try await runtime.checkModel(Fixtures.configuration(.openAI, model: "gpt-6-luna", tools: [.dateTime, .webSearch]))

        let body = try Fixtures.body(transport.requests.value[0])
        #expect(body["instructions"] == .string(CloudCleanupRuntime.modelCheckSystemPrompt))
        #expect(body["tools"] == nil)
    }

    @Test
    func modelCheckReportsAMissingModel() async {
        let transport = FakeTransport([(404, ["error": ["message": "The model `gpt-9` does not exist."]])])
        let runtime = CloudCleanupRuntime(send: transport.send, context: CloudRuntimeContext(timeZone: .gmt))

        await #expect(throws: CloudCleanupError.http(status: 404, message: "The model `gpt-9` does not exist.")) {
            try await runtime.checkModel(Fixtures.configuration(.openAI, model: "gpt-9"))
        }
    }

    @Test
    func httpErrorCarriesTheProviderMessage() async {
        let transport = FakeTransport([(401, ["error": ["message": "Incorrect API key provided."]])])
        let runtime = CloudCleanupRuntime(send: transport.send, context: CloudRuntimeContext(timeZone: .gmt))

        await #expect(throws: CloudCleanupError.http(status: 401, message: "Incorrect API key provided.")) {
            try await runtime.clean("hi", configuration: Fixtures.configuration(.openAI, model: "gpt-6-luna"))
        }
        #expect(CloudCleanupError.http(status: 401, message: nil).isAuthenticationFailure)
    }

    @Test
    func emptyAnswerIsAnError() async {
        let transport = FakeTransport([(200, ["choices": [["message": ["role": "assistant", "content": "  "]]]])])
        let runtime = CloudCleanupRuntime(send: transport.send, context: CloudRuntimeContext(timeZone: .gmt))

        await #expect(throws: CloudCleanupError.emptyResponse) {
            try await runtime.clean("hi", configuration: Fixtures.configuration(.openRouter, model: "openai/gpt-6-luna"))
        }
    }

    @Test
    func endlessToolCallsStopAtTheRequestLimit() async {
        let toolCall: JSONValue = ["choices": [["message": [
            "role": "assistant",
            "tool_calls": [["id": "call_1", "type": "function", "function": ["name": "get_current_date_time", "arguments": "{}"]]],
        ]]]]
        let transport = FakeTransport(Array(repeating: (200, toolCall), count: CloudCleanupRuntime.maxRequests))
        let runtime = CloudCleanupRuntime(send: transport.send, context: CloudRuntimeContext(timeZone: .gmt))

        await #expect(throws: CloudCleanupError.tooManyToolCalls) {
            try await runtime.clean("hi", configuration: Fixtures.configuration(.openRouter, model: "openai/gpt-6-luna", tools: [.dateTime]))
        }
        #expect(transport.requests.value.count == CloudCleanupRuntime.maxRequests)
    }
}

enum Fixtures {
    static func configuration(_ provider: CloudProvider, model: CloudModel.ID, tools: Set<CloudTool> = []) -> CloudCleanupConfiguration {
        CloudCleanupConfiguration(
            connection: CloudConnection(provider: provider, apiKey: "sk-test"),
            model: model,
            systemPrompt: "Clean the <transcript>.",
            tools: tools
        )
    }

    static let screenshot = Data([0xFF, 0xD8, 0xFF])

    static func body(_ request: URLRequest) throws -> JSONValue {
        try JSONValue.decode(try #require(request.httpBody))
    }

    static func userMessage(in body: JSONValue) -> JSONValue? {
        body["input"]?[0] ?? body["messages"]?.arrayValue?.last
    }
}

final class FakeTransport: Sendable {
    let requests = LockIsolated<[URLRequest]>([])
    private let responses: LockIsolated<[(Int, JSONValue)]>

    init(_ responses: [(Int, JSONValue)]) {
        self.responses = LockIsolated(responses)
    }

    @Sendable
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.withValue { $0.append(request) }
        let (status, body) = responses.withValue { $0.removeFirst() }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (try body.encoded(), response)
    }
}

@Suite
struct CloudPromptTokenTests {
    @Test
    func scanFindsTagsKnownVariablesAndTypos() {
        let tokens = CloudPromptToken.scan("Clean <transcript> for {{app}} on {{dat}}.</transcript>")
        expectNoDifference(tokens, [
            CloudPromptToken(kind: .tag, range: NSRange(location: 6, length: 12)),
            CloudPromptToken(kind: .variable(.app), range: NSRange(location: 23, length: 7)),
            CloudPromptToken(kind: .unknownVariable, range: NSRange(location: 34, length: 7)),
            CloudPromptToken(kind: .tag, range: NSRange(location: 42, length: 13)),
        ])
    }

    @Test
    func everyVariableTokenScansAsKnown() {
        for variable in CloudPromptVariable.allCases {
            #expect(CloudPromptToken.scan(variable.token).map(\.kind) == [.variable(variable)])
        }
    }
}
