extension Ghostty {
    /// Possible errors from internal Ghostty calls.
    enum Error: Swift.Error, CustomLocalizedStringResourceConvertible {
        case apiFailed

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .apiFailed: return "Terminal engine API call failed"
            }
        }
    }
}
