import Foundation
import ImageIO
import SwiftUI
import Testing
@testable import UI

/// Renders stage capsule frames offscreen for visual review.
/// Run with `TEST_RUNNER_PETAL_CAPSULE_CAPTURE_DIR=<dir> xcodebuild test …`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PETAL_CAPSULE_CAPTURE_DIR"] != nil))
struct CapsuleRenderTests {
    private typealias Curve = CapsuleChoreography

    private enum Backdrop: String, CaseIterable {
        case light
        case dark
        case busy
    }

    private struct Shot {
        var name: String
        var time: Double
        var phase: FloatingCapsuleState.Phase
        var interaction: CapsuleRecordingInteraction = .idle
    }

    /// The session as it is known at `time`: events that have not happened yet are left out.
    private static func timeline(at time: Double) -> CapsuleTimeline {
        let events: [(Double, (inout CapsuleTimeline, Double) -> Void)] = [
            (0, { $0.present(size: CapsuleTimeline.defaultSize, glow: FloatingCapsuleState.Phase.recording.capsuleGlow, at: $1) }),
            (2, { $0.setSplit(true, at: $1) }),
            (2.5, { $0.setHover(stop: false, transcribe: true, at: $1) }),
            (2.8, { $0.setHover(stop: true, transcribe: false, at: $1) }),
            (3.3, { $0.setHover(stop: false, transcribe: false, at: $1) }),
            (3.5, { $0.setSplit(false, at: $1) }),
            (4, { $0.pulse(at: $1); $0.setGlow(FloatingCapsuleState.Phase.transcribing.capsuleGlow, at: $1) }),
            (6, { $0.pulse(at: $1); $0.setGlow(FloatingCapsuleState.Phase.copiedToClipboard.capsuleGlow, at: $1) }),
            (8, { $0.dismiss(at: $1) }),
        ]
        var timeline = CapsuleTimeline()
        for (eventTime, apply) in events where eventTime <= time {
            apply(&timeline, eventTime)
        }
        return timeline
    }

    private static let shots: [Shot] = [
        Shot(name: "01-drop", time: 0.08, phase: .recording),
        Shot(name: "02-grow", time: 0.16, phase: .recording),
        Shot(name: "03-ripple", time: 0.30, phase: .recording),
        Shot(name: "04-rise", time: 0.60, phase: .recording),
        Shot(name: "05-recording", time: 1.80, phase: .recording),
        Shot(name: "06-split-neck", time: 2.10, phase: .recording, interaction: .hovered),
        Shot(name: "07-split", time: 2.20, phase: .recording, interaction: .hovered),
        Shot(name: "08a-transcribe-hover", time: 2.75, phase: .recording, interaction: .hovered),
        Shot(name: "08b-stop-hover", time: 3.20, phase: .recording, interaction: .hovered),
        Shot(name: "08c-hover-out", time: 3.45, phase: .recording, interaction: .hovered),
        Shot(name: "09-merge", time: 3.62, phase: .recording),
        Shot(name: "10-pulse", time: 4.10, phase: .transcribing),
        Shot(name: "11-pulse-ripple", time: 4.35, phase: .transcribing),
        Shot(name: "12-transcribing", time: 5.50, phase: .transcribing),
        Shot(name: "13-copied", time: 7.00, phase: .copiedToClipboard),
        Shot(name: "14-dismiss", time: 8.08, phase: .copiedToClipboard),
        Shot(name: "15-dismiss-shrink", time: 8.18, phase: .copiedToClipboard),
        Shot(name: "16-dismiss-lift", time: 8.32, phase: .copiedToClipboard),
    ]

    @Test func renderFrames() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PETAL_CAPSULE_CAPTURE_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = FloatingCapsuleState()
        state.level = 0.6

        var materials: [(String, CapsuleStage.Material)] = [("future", .future)]
        if #available(macOS 26.0, *) {
            materials.append(("glass", .systemGlass))
        }
        for (materialName, material) in materials {
        for backdrop in Backdrop.allCases {
            for shot in Self.shots {
                state.phase = shot.phase
                let scheme: ColorScheme = material == .future || backdrop != .light ? .dark : .light
                let scene = CapsuleScene(frame: Self.timeline(at: shot.time).frame(at: shot.time), material: material) {
                    Group {
                        if shot.phase == .recording {
                            CapsuleRecordingPill(level: 0.6, interaction: shot.interaction) {}
                        } else {
                            FloatingCapsulePhaseContent(state: state, phase: shot.phase, blur: 0)
                        }
                    }
                    .fixedSize()
                    .environment(\.capsuleStageDrawsGlass, true)
                    .environment(\.colorScheme, scheme)
                } secondary: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: Curve.secondarySize.width, height: Curve.secondarySize.height)
                }
                let view = scene
                    .background { background(backdrop) }
                    .environment(\.colorScheme, backdrop == .light ? .light : .dark)
                try write(view, to: directory.appendingPathComponent("\(materialName)-\(backdrop.rawValue)-\(shot.name).png"))
            }
        }
        }
    }

    @Test func renderCausticShimmer() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PETAL_CAPSULE_CAPTURE_DIR"]))
            .appendingPathComponent("caustic")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let frame = Self.timeline(at: 1.9).frame(at: 1.9)
        for (time, level) in [(0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0), (4.0, 0.0), (2.0, 0.9)] {
            let scene = CapsuleScene(frame: frame, caustic: [time, level]) {
                CapsuleRecordingPill(level: 0.6, interaction: .idle) {}
                    .fixedSize()
                    .environment(\.colorScheme, .dark)
            } secondary: {
                EmptyView()
            }
            try write(
                scene.background { background(.dark) },
                to: directory.appendingPathComponent("caustic-t\(time)-level\(level).png")
            )
        }
    }

    @ViewBuilder
    private func background(_ backdrop: Backdrop) -> some View {
        switch backdrop {
        case .light:
            ZStack(alignment: .topLeading) {
                Color(white: 0.96)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0 ..< 8, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(white: 0.78))
                            .frame(width: CGFloat(180 + (index * 53) % 200), height: 7)
                    }
                }
                .padding(20)
            }
        case .dark:
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.12, blue: 0.20), Color(red: 0.05, green: 0.05, blue: 0.09)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .busy:
            LinearGradient(
                colors: [.orange, .pink, .blue, .teal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func write(_ view: some View, to url: URL) throws {
        let renderer = ImageRenderer(content: view.frame(width: Curve.stageSize.width, height: Curve.stageSize.height))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
