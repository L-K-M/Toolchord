/// How large the palette draws its interface text: list rows, labels,
/// hints, and the search field. The panel grows with it.
///
/// Raw values are stored in user defaults.
public enum InterfaceTextSize: String, Sendable, CaseIterable, Codable, Identifiable {
    case small
    case standard
    case large
    case extraLarge

    public var id: String { rawValue }

    /// The factor applied to every interface font size and to the panel.
    public var scale: Double {
        switch self {
        case .small: 0.9
        case .standard: 1
        case .large: 1.15
        case .extraLarge: 1.3
        }
    }

    public var label: String {
        switch self {
        case .small: "Small"
        case .standard: "Standard"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }
}
