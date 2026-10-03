public struct ModelCatalogEntry: Codable, Equatable, Identifiable, Sendable {
    public typealias ID = Tagged<Self, String>

    public var id: ID
    public var name: String
    public var summary: String
    public var provider: String
    public var size: String?
    public var isRecommended: Bool
    public var isDownloaded: Bool
    public var supportsLiveTranscription: Bool

    public static func catalog(isDownloaded: (ModelOption) -> Bool) -> IdentifiedArrayOf<Self> {
        IdentifiedArray(uniqueElements: ModelOption.allCases.map { option in
            ModelCatalogEntry(
                id: ID(rawValue: option.rawValue),
                name: option.displayName,
                summary: option.summary,
                provider: option.providerDisplayName,
                size: option.sizeLabel,
                isRecommended: option.isRecommended,
                isDownloaded: !option.requiresDownload || isDownloaded(option),
                supportsLiveTranscription: option.supportsStreamingTranscription
            )
        })
    }
}
