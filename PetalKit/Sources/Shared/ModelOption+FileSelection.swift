public extension ModelOption {
    static func fileOverride(
        id: String, dictationModel: Self?, available: [Self] = allCases,
        isReady: (Self) -> Bool
    ) -> Self? {
        guard let option = Self(rawValue: id), available.contains(option),
              option != dictationModel, isReady(option)
        else { return nil }
        return option
    }
}
