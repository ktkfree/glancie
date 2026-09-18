import SwiftUI

/// Global design tokens — iOS-style 4pt grid, continuous corner radii, SF Rounded type ramp.
public enum Metric {
    /// Main floating bar height (Dynamic Island proportions, scaled for macOS density)
    public static let barHeight: CGFloat = 34
    /// Bleed room around the panel so ambient glow + shadows are not clipped
    public static let panelBleed: CGFloat = 20
    /// Gap between the bar and the detail card
    public static let stackGap: CGFloat = 10

    public static let panelWidth: CGFloat = 380
    public static let detailWidth: CGFloat = 318

    /// Top band of the panel treated as the draggable bar (bleed + bar + slack)
    public static let barBand: CGFloat = panelBleed + barHeight + 4
    /// Strip reserved above the bar for the pixel cat companion. The bar sits
    /// this much lower in the window whenever the cat is on, so anything that
    /// measures down from the window's top edge has to add it back.
    public static let pixelCatBand: CGFloat = 20

    /// Menu bar dropdown content width, excluding shadow bleed
    public static let menuWidth: CGFloat = 336
    /// Shadow bleed around the menu dropdown so the elevation stack is not clipped
    public static let menuBleed: CGFloat = 18
    /// Ceiling for the dropdown before its content starts scrolling
    public static let menuMaxContentHeight: CGFloat = 560

    // 4pt spacing scale
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 20
}

public enum Radius {
    /// Full capsule for the main bar
    public static let bar: CGFloat = Metric.barHeight / 2
    /// Provider chip inside the bar
    public static let chip: CGFloat = 11
    /// iOS "inset grouped" section
    public static let section: CGFloat = 14
    /// Settings-style icon tile
    public static let tile: CGFloat = 7
    /// Detail card / popover shell
    public static let card: CGFloat = 22
    /// Menu bar dropdown shell — matches the system menu corner in macOS Tahoe
    public static let menu: CGFloat = 14
    /// Highlight behind a hovered menu command row
    public static let menuRow: CGFloat = 7
}

/// SF Rounded type ramp. Rounded everywhere is the single strongest "iOS feel" lever
/// for a numeric, glanceable HUD.
public enum GlancieFont {
    public static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Big hero readout (ring center)
    public static let hero = rounded(28, .bold)
    /// Card / popover title
    public static let title = rounded(15, .bold)
    /// Row label
    public static let row = rounded(12, .medium)
    /// Numeric value in the bar
    public static let barValue = rounded(11.5, .semibold)
    /// Supporting caption
    public static let caption = rounded(10.5, .medium)
    /// Uppercase section header
    public static let sectionHeader = rounded(9.5, .bold)
}

public extension Text {
    /// iOS grouped-list section header treatment
    func sectionHeaderStyle() -> some View {
        self
            .font(GlancieFont.sectionHeader)
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}
