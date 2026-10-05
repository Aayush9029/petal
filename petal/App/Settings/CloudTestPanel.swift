import CloudCleanupClient
import RouterFeature
import Shared
import SwiftUI
import UI

struct CloudTestPanel: View {
    @Binding var sample: String
    let testRun: RouterModel.TestRun
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                line("You say") {
                    TextField("Type what you would dictate", text: $sample, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1 ... 5)
                        .foregroundStyle(.secondary)
                }
                line("Petal writes") { output }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))

            HStack {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                if testRun.is(\.running) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 52, height: 24)
                } else {
                    SettingsActionButton(title: "Run", action: onRun)
                        .disabled(sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(16)
        .animation(.easeOut(duration: 0.18), value: testRun)
    }

    @ViewBuilder
    private var output: some View {
        switch testRun {
        case .idle:
            Text("Press Run to clean up this sample with these instructions.")
                .foregroundStyle(.tertiary)
        case .running:
            Text("Writing…")
                .animatedIntelligenceGradient()
                .shimmering()
        case let .finished(result):
            Text(result.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .animatedIntelligenceGradient()
                .contentTransition(.opacity)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private var footnote: String {
        guard case let .finished(result) = testRun else { return "Uses the same model and tools as dictation." }
        let seconds = Double(result.elapsed.components.seconds) + Double(result.elapsed.components.attoseconds) / 1e18
        var parts = ["\(seconds.formatted(.number.precision(.fractionLength(1)))) s"]
        if let model = result.model {
            parts.append(model.rawValue)
        }
        if !result.toolCalls.isEmpty {
            let tools = CloudTool.allCases.filter { tool in result.toolCalls.contains { $0 == tool.functionName } }
            parts.append("Used \(tools.map(\.title).joined(separator: ", "))")
        }
        return parts.joined(separator: " · ")
    }

    private func line(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    @Previewable @State var sample = "um so can you like send the the report to sam by friday no wait thursday"
    VStack(spacing: 0) {
        CloudTestPanel(sample: $sample, testRun: .idle) {}
        CloudTestPanel(sample: $sample, testRun: .running) {}
        CloudTestPanel(
            sample: $sample,
            testRun: .finished(CloudCleanupResult(
                text: "So, can you send the report to Sam by Thursday?",
                model: "gpt-6-luna",
                elapsed: .milliseconds(1240)
            ))
        ) {}
        CloudTestPanel(sample: $sample, testRun: .failed("Incorrect API key provided. (HTTP 401)")) {}
    }
    .frame(width: 500)
}
