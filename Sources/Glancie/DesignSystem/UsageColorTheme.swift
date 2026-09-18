import SwiftUI

/// Quota tier — one place that owns color, glow, wording and symbol for a given
/// remaining percentage. Meaning is never carried by color alone: every tier
/// ships a label and a distinct SF Symbol too (HIG accessibility requirement).
public enum UsageTier: String, CaseIterable {
    case abundant   // 75 ~ 100
    case steady     // 45 ~ 74
    case caution    // 20 ~ 44
    case critical   // 0  ~ 19

    public static func from(_ percentage: Double) -> UsageTier {
        switch max(0, min(100, percentage)) {
        case 75...100: return .abundant
        case 45..<75:  return .steady
        case 20..<45:  return .caution
        default:       return .critical
        }
    }

    /// Solid & deep tone palette (crisp, high-contrast, non-pastel).
    public var gradient: [Color] {
        switch self {
        case .abundant: return [Color(hex: 0x28CD41), Color(hex: 0x188028)] // Deep vibrant green
        case .steady:   return [Color(hex: 0x0A84FF), Color(hex: 0x0050C7)] // Deep solid royal blue
        case .caution:  return [Color(hex: 0xFF9F0A), Color(hex: 0xC25B00)] // Rich deep amber orange
        case .critical: return [Color(hex: 0xFF453A), Color(hex: 0xB31B1B)] // Deep vivid crimson red
        }
    }

    public var accent: Color { gradient[0] }
    public var deep: Color { gradient[1] }

    /// Status wording shown next to the ring
    public var label: String {
        switch self {
        case .abundant: return L10n.tierAbundant.text
        case .steady:   return L10n.tierSteady.text
        case .caution:  return L10n.tierCaution.text
        case .critical: return L10n.tierCritical.text
        }
    }

    public var symbol: String {
        switch self {
        case .abundant: return "bolt.fill"
        case .steady:   return "checkmark.circle.fill"
        case .caution:  return "exclamationmark.triangle.fill"
        case .critical: return "hourglass"
        }
    }
}

/// Provider-agnostic color system based strictly on remaining quota percentage.
public enum UsageColorTheme {
    public static func tier(for percentage: Double) -> UsageTier {
        UsageTier.from(percentage)
    }

    /// Gradient colors for a given remaining percentage (0.0 ~ 100.0)
    public static func gradientColors(for percentage: Double) -> [Color] {
        UsageTier.from(percentage).gradient
    }

    /// Primary accent color representing the remaining percentage
    public static func primaryColor(for percentage: Double) -> Color {
        UsageTier.from(percentage).accent
    }
}

public extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}
