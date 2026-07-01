import Shared
import SwiftUI

extension SettingsTab {
    var title: String {
        switch self {
        case .general: "General"
        case .transcription: "Transcription"
        case .recording: "Recording"
        case .history: "History"
        case .advanced: "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .transcription: "waveform"
        case .recording: "mic"
        case .history: "clock"
        case .advanced: "slider.horizontal.3"
        }
    }

    var fill: Color {
        switch self {
        case .general: .indigo
        case .transcription: .purple
        case .recording: .pink
        case .history: .orange
        case .advanced: .gray
        }
    }
}
