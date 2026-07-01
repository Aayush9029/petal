import IdentifiedCollections

public struct ModelOptionProviderGroup: Identifiable, Equatable, Sendable {
    public var id: String {
        provider.rawValue
    }

    public var provider: ModelProvider
    public var options: IdentifiedArrayOf<ModelOption>

    public var title: String {
        provider.modelListDisplayName
    }

    public init(
        provider: ModelProvider,
        options: IdentifiedArrayOf<ModelOption>
    ) {
        self.provider = provider
        self.options = options
    }
}

public extension ModelProvider {
    var modelListDisplayName: String {
        switch self {
        case .appleSpeech:
            return "Built In"
        case .fluidAudio:
            return "Qwen"
        case .nvidia:
            return "NVIDIA"
        case .whisperKit:
            return "Whisper"
        case .voxtralCore:
            return "Voxtral"
        }
    }
}

public extension ModelOption {
    static func providerGroups(
        for options: [Self] = Self.allCases,
        excluding excludedOption: Self? = nil
    ) -> IdentifiedArrayOf<ModelOptionProviderGroup> {
        var groups: IdentifiedArrayOf<ModelOptionProviderGroup> = []

        for option in options where option != excludedOption {
            if var group = groups[id: option.provider.rawValue] {
                group.options.append(option)
                groups[id: group.id] = group
            } else {
                groups.append(
                    ModelOptionProviderGroup(
                        provider: option.provider,
                        options: [option]
                    )
                )
            }
        }

        return groups
    }
}
