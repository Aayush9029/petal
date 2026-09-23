import Shared
import SwiftUI

extension SettingsTab {
    var title: String {
        switch self {
        case .general: "General"
        case .transcription: "Models"
        case .intelligence: "Intelligence"
        case .recording: "Recording"
        case .history: "History"
        case .advanced: "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .transcription: "cube"
        case .intelligence: "sparkles"
        case .recording: "mic"
        case .history: "clock"
        case .advanced: "slider.horizontal.3"
        }
    }

    var fill: Color {
        switch self {
        case .general: .indigo
        case .transcription: .purple
        case .intelligence: .blue
        case .recording: .pink
        case .history: .orange
        case .advanced: .gray
        }
    }
}
