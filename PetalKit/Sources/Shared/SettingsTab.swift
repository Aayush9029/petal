import CasePaths

@CasePathable
public enum SettingsTab: Hashable, CaseIterable, Sendable {
    case general
    case transcription
    case intelligence
    case recording
    case history
    case advanced
}
