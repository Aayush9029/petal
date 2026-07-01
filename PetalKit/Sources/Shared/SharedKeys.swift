import Foundation
import Sharing

public extension SharedKey where Self == AppStorageKey<Bool>.Default {
    static var hasCompletedSetup: Self {
        Self[.appStorage("has_completed_setup"), default: false]
    }

    static var trimSilenceEnabled: Self {
        Self[.appStorage("trim_silence_enabled"), default: false]
    }

    static var autoSpeedEnabled: Self {
        Self[.appStorage("auto_speed_enabled"), default: false]
    }

    static var compressHistoryAudio: Self {
        Self[.appStorage("compress_history_audio"), default: false]
    }

    static var appleIntelligenceEnabled: Self {
        Self[.appStorage("apple_intelligence_enabled"), default: false]
    }

    static var logsEnabled: Self {
        Self[.appStorage("logs_enabled"), default: false]
    }

    static var restoreClipboardAfterPaste: Self {
        Self[.appStorage("restore_clipboard_after_paste"), default: true]
    }

    static var duckSystemAudioDuringRecording: Self {
        Self[.appStorage("duck_system_audio_during_recording"), default: false]
    }
}

public extension SharedKey where Self == AppStorageKey<String>.Default {
    static var selectedModelID: Self {
        Self[.appStorage("selected_model_id"), default: ModelOption.defaultOption.rawValue]
    }

    static var selectedAudioInputDeviceID: Self {
        Self[.appStorage("selected_audio_input_device_id"), default: "system-default"]
    }

    static var smartPrompt: Self {
        Self[.appStorage("smart_prompt"), default: "Clean up filler words and repeated phrases. Return a polished version of what was said."]
    }
}

public extension SharedKey where Self == AppStorageKey<TranscriptionMode>.Default {
    static var transcriptionMode: Self {
        Self[.appStorage("transcription_mode"), default: .verbatim]
    }
}

public extension SharedKey where Self == AppStorageKey<PushToTalkThreshold>.Default {
    static var pushToTalkThreshold: Self {
        Self[.appStorage("push_to_talk_threshold"), default: .long]
    }
}

public extension SharedKey where Self == AppStorageKey<HistoryRetentionMode>.Default {
    static var historyRetentionMode: Self {
        Self[.appStorage("history_retention_mode"), default: .both]
    }
}

public extension SharedKey where Self == AppStorageKey<ShortcutTriggerMode>.Default {
    static var shortcutTriggerMode: Self {
        Self[.appStorage("shortcut_trigger_mode"), default: .combo]
    }
}

public extension SharedKey where Self == AppStorageKey<Double>.Default {
    static var doubleTapInterval: Self {
        Self[.appStorage("double_tap_interval"), default: 0.4]
    }
}

public extension SharedKey where Self == AppStorageKey<DoubleTapKey>.Default {
    static var doubleTapKey: Self {
        Self[.appStorage("double_tap_key"), default: .unconfigured]
    }
}

public extension SharedKey where Self == FileStorageKey<[TranscriptHistoryDay]>.Default {
    static var transcriptHistoryDays: Self {
        Self[
            .fileStorage(
                .documentsDirectory
                    .appending(component: "petal")
                    .appending(component: "history")
                    .appending(component: "history.json")
            ),
            default: []
        ]
    }
}
