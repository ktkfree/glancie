import SwiftUI
import AppKit

/// Appearance-adaptive surface tokens.
///
/// Every token resolves through AppKit at draw time, so one value renders
/// correctly in both appearances. This matters more than it sounds: a rim drawn
/// as `Color.white.opacity(0.18)` disappears against a light panel, and a plate
/// drawn as a fixed light gray becomes a glowing slab in Dark Mode. Tokens keep
/// both cases honest.
public enum Surface {
    private struct RGBA {
        let r: Double, g: Double, b: Double, a: Double
    }

    private static func adaptive(light: RGBA, dark: RGBA) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
        })
    }

    // MARK: - Glass shell

    /// Tint laid over the frosted backdrop to give the shell a body of its own.
    ///
    /// Deliberately a neutral frost rather than paper white in Light Mode: plates
    /// sitting on the shell are near-white, so a white shell would flatten the two
    /// into one another and the grouping would stop reading.
    public static let shellTint = adaptive(
        light: RGBA(r: 0.918, g: 0.928, b: 0.945, a: 0.74),
        dark: RGBA(r: 0.125, g: 0.13, b: 0.145, a: 0.62)
    )

    /// Same as `shellTint` but at the density used while hovered.
    public static let shellTintHovered = adaptive(
        light: RGBA(r: 0.948, g: 0.956, b: 0.970, a: 0.82),
        dark: RGBA(r: 0.155, g: 0.16, b: 0.175, a: 0.70)
    )

    /// Outer rim. Dark hairline in Light Mode, light hairline in Dark Mode —
    /// the inverse of the surface, which is what keeps an edge crisp.
    public static let shellRim = adaptive(
        light: RGBA(r: 0, g: 0, b: 0, a: 0.11),
        dark: RGBA(r: 1, g: 1, b: 1, a: 0.15)
    )

    /// Specular highlight riding the top edge, simulating a light source above.
    public static let topSheen = adaptive(
        light: RGBA(r: 1, g: 1, b: 1, a: 0.78),
        dark: RGBA(r: 1, g: 1, b: 1, a: 0.13)
    )

    // MARK: - Raised plates (inset grouped sections)

    /// Brighter than the shell in both appearances, which is what makes a plate
    /// read as raised without needing a heavy border.
    public static let plateFill = adaptive(
        light: RGBA(r: 1, g: 1, b: 1, a: 0.82),
        dark: RGBA(r: 1, g: 1, b: 1, a: 0.055)
    )

    public static let plateRim = adaptive(
        light: RGBA(r: 0, g: 0, b: 0, a: 0.07),
        dark: RGBA(r: 1, g: 1, b: 1, a: 0.075)
    )

    // MARK: - Separators & tracks

    public static let hairline = adaptive(
        light: RGBA(r: 0, g: 0, b: 0, a: 0.10),
        dark: RGBA(r: 1, g: 1, b: 1, a: 0.095)
    )

    /// Unfilled portion of any gauge.
    public static let track = adaptive(
        light: RGBA(r: 0, g: 0, b: 0, a: 0.10),
        dark: RGBA(r: 1, g: 1, b: 1, a: 0.14)
    )

    // MARK: - Interaction states

    /// Hover wash for content rows that should lift rather than fully highlight.
    public static let hoverWash = adaptive(
        light: RGBA(r: 0, g: 0, b: 0, a: 0.045),
        dark: RGBA(r: 1, g: 1, b: 1, a: 0.07)
    )

    public static let pressWash = adaptive(
        light: RGBA(r: 0, g: 0, b: 0, a: 0.085),
        dark: RGBA(r: 1, g: 1, b: 1, a: 0.115)
    )

    // MARK: - Shadow stack

    /// Wide atmospheric spread.
    static let shadowDiffuse = adaptive(
        light: RGBA(r: 0, g: 0, b: 0, a: 0.17),
        dark: RGBA(r: 0, g: 0, b: 0, a: 0.42)
    )

    /// Mid-range elevation cue.
    static let shadowMid = adaptive(
        light: RGBA(r: 0, g: 0, b: 0, a: 0.10),
        dark: RGBA(r: 0, g: 0, b: 0, a: 0.26)
    )

    /// Tight contact occlusion that anchors the shape to its backdrop.
    static let shadowContact = adaptive(
        light: RGBA(r: 0, g: 0, b: 0, a: 0.09),
        dark: RGBA(r: 0, g: 0, b: 0, a: 0.20)
    )
}

/// Three-tier ambient shadow. Composited in SwiftUI rather than delegated to
/// `NSWindow.hasShadow`, because a window shadow is derived from content alpha
/// and lags a frame behind every resize on a translucent panel.
public struct AmbientElevation: ViewModifier {
    public var elevation: CGFloat

    public init(elevation: CGFloat = 1.0) {
        self.elevation = max(0, elevation)
    }

    public func body(content: Content) -> some View {
        content
            .shadow(color: Surface.shadowDiffuse, radius: 18 * elevation, x: 0, y: 10 * elevation)
            .shadow(color: Surface.shadowMid, radius: 6 * elevation, x: 0, y: 3 * elevation)
            .shadow(color: Surface.shadowContact, radius: 1.5, x: 0, y: 1)
    }
}

public extension View {
    /// Layered ambient shadow. `elevation` scales the two outer tiers; the
    /// contact tier stays fixed so surfaces never lose their grounding.
    func ambientElevation(_ elevation: CGFloat = 1.0) -> some View {
        modifier(AmbientElevation(elevation: elevation))
    }

    /// Hairline rule matching the system separator weight in both appearances.
    func hairlineRule() -> some View {
        overlay(alignment: .top) {
            Rectangle()
                .fill(Surface.hairline)
                .frame(height: 0.5)
        }
    }
}
