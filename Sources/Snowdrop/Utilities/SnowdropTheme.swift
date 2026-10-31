import SwiftUI

// MARK: - SnowdropTheme

/// Colour themes. A theme sets the accent colour and the tinted glow that sits
/// behind the translucent window; the glass itself comes from the system.
enum SnowdropTheme: String, CaseIterable, Identifiable {
    case snowdrop
    case midnight
    case sakura
    case amber
    case ocean
    case forest
    case aurora
    case graphite

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .snowdrop: String(localized: "Snowdrop")
        case .midnight: String(localized: "Midnight")
        case .sakura: String(localized: "Sakura")
        case .amber: String(localized: "Amber")
        case .ocean: String(localized: "Ocean")
        case .forest: String(localized: "Forest")
        case .aurora: String(localized: "Aurora")
        case .graphite: String(localized: "Graphite")
        }
    }

    /// Accent used for tint, selection and progress.
    var accent: Color {
        switch self {
        case .snowdrop: Color(red: 0.42, green: 0.72, blue: 0.95)
        case .midnight: Color(red: 0.55, green: 0.50, blue: 0.98)
        case .sakura: Color(red: 0.98, green: 0.45, blue: 0.67)
        case .amber: Color(red: 0.96, green: 0.65, blue: 0.20)
        case .ocean: Color(red: 0.20, green: 0.78, blue: 0.80)
        case .forest: Color(red: 0.36, green: 0.80, blue: 0.48)
        case .aurora: Color(red: 0.40, green: 0.95, blue: 0.70)
        case .graphite: Color(red: 0.72, green: 0.74, blue: 0.78)
        }
    }

    /// Two colours blended into the background glow, top-leading to bottom-trailing.
    var glow: (Color, Color) {
        switch self {
        case .snowdrop: (Color(red: 0.55, green: 0.80, blue: 0.98), Color(red: 0.80, green: 0.90, blue: 1.00))
        case .midnight: (Color(red: 0.20, green: 0.15, blue: 0.45), Color(red: 0.05, green: 0.05, blue: 0.18))
        case .sakura: (Color(red: 0.95, green: 0.55, blue: 0.72), Color(red: 0.55, green: 0.25, blue: 0.45))
        case .amber: (Color(red: 0.90, green: 0.55, blue: 0.15), Color(red: 0.40, green: 0.15, blue: 0.10))
        case .ocean: (Color(red: 0.05, green: 0.50, blue: 0.62), Color(red: 0.03, green: 0.15, blue: 0.35))
        case .forest: (Color(red: 0.12, green: 0.45, blue: 0.28), Color(red: 0.04, green: 0.16, blue: 0.12))
        case .aurora: (Color(red: 0.10, green: 0.65, blue: 0.55), Color(red: 0.35, green: 0.20, blue: 0.65))
        case .graphite: (Color(red: 0.30, green: 0.31, blue: 0.34), Color(red: 0.10, green: 0.10, blue: 0.12))
        }
    }

    /// Glow strength in the opaque (non-transparent) window. The icy theme
    /// stays light, the others are deep.
    var glowOpacity: Double {
        self == .snowdrop ? 0.35 : 0.55
    }
}
