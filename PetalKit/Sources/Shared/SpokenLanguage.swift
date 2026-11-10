/// A language that the user fixes for models that can otherwise detect the wrong one.
public enum SpokenLanguage: String, CaseIterable, Identifiable, Sendable {
    case arabic = "ar"
    case cantonese = "yue"
    case chinese = "zh"
    case czech = "cs"
    case danish = "da"
    case dutch = "nl"
    case english = "en"
    case filipino = "tl"
    case finnish = "fi"
    case french = "fr"
    case german = "de"
    case greek = "el"
    case hindi = "hi"
    case hungarian = "hu"
    case indonesian = "id"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case macedonian = "mk"
    case malay = "ms"
    case persian = "fa"
    case polish = "pl"
    case portuguese = "pt"
    case romanian = "ro"
    case russian = "ru"
    case spanish = "es"
    case swedish = "sv"
    case thai = "th"
    case turkish = "tr"
    case vietnamese = "vi"

    public var id: String { rawValue }

    /// The ISO code, which Whisper expects.
    public var code: String { rawValue }

    /// The English name, which Qwen3 ASR expects.
    public var name: String {
        switch self {
        case .arabic: "Arabic"
        case .cantonese: "Cantonese"
        case .chinese: "Chinese"
        case .czech: "Czech"
        case .danish: "Danish"
        case .dutch: "Dutch"
        case .english: "English"
        case .filipino: "Filipino"
        case .finnish: "Finnish"
        case .french: "French"
        case .german: "German"
        case .greek: "Greek"
        case .hindi: "Hindi"
        case .hungarian: "Hungarian"
        case .indonesian: "Indonesian"
        case .italian: "Italian"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .macedonian: "Macedonian"
        case .malay: "Malay"
        case .persian: "Persian"
        case .polish: "Polish"
        case .portuguese: "Portuguese"
        case .romanian: "Romanian"
        case .russian: "Russian"
        case .spanish: "Spanish"
        case .swedish: "Swedish"
        case .thai: "Thai"
        case .turkish: "Turkish"
        case .vietnamese: "Vietnamese"
        }
    }
}
