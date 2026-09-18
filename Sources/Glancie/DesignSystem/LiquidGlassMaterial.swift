import SwiftUI
import AppKit

/// Visual Effect View wrapper for macOS Glassmorphism
public struct VisualEffectBackground: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State
    public var isEmphasized: Bool

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active,
        isEmphasized: Bool = true
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.isEmphasized = isEmphasized
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.isEmphasized = isEmphasized
    }
}

/// Liquid Glass: frosted backdrop, adaptive body tint, interior colour bloom,
/// a directional specular rim, and the layered ambient shadow stack.
///
/// The rim is drawn as two passes — a bright gradient biased to the top-left and
/// a neutral hairline all round — because a uniform stroke reads as a drawn
/// outline, whereas a biased one reads as light refracting through an edge.
public struct LiquidGlassStyle: ViewModifier {
    public var cornerRadius: CGFloat
    public var tint: Color
    public var isHovered: Bool
    /// Scales the outer shadow tiers. The bar sits close to the desktop; cards float higher.
    public var elevation: CGFloat
    /// Scales the interior colour bloom. The same alpha reads far stronger across a
    /// large card than across a 34pt bar, so big surfaces dial it back.
    public var tintStrength: CGFloat

    public init(
        cornerRadius: CGFloat = Radius.bar,
        tint: Color = .clear,
        isHovered: Bool = false,
        elevation: CGFloat = 1.0,
        tintStrength: CGFloat = 1.0
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.isHovered = isHovered
        self.elevation = elevation
        self.tintStrength = tintStrength
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    public func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // 1 — Frosted backdrop sampling the desktop behind the window
                    VisualEffectBackground(material: .popover, blendingMode: .behindWindow)

                    // 2 — Adaptive body tint so the shell has substance in both appearances
                    (isHovered ? Surface.shellTintHovered : Surface.shellTint)

                    // 3 — Interior colour bloom carrying the active quota tier
                    RadialGradient(
                        colors: [tint.opacity((isHovered ? 0.16 : 0.10) * tintStrength), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: cornerRadius * 7
                    )

                    // 4 — Top-edge sheen: the surface catching an overhead light
                    LinearGradient(
                        colors: [Surface.topSheen, .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
                .clipShape(shape)
            }
            .overlay {
                // 5 — Directional specular rim (bright top-left, fading away)
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Surface.topSheen,
                            Surface.shellRim.opacity(0.35),
                            Surface.shellRim
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
            }
            .overlay {
                // 6 — Neutral closing hairline so the edge never dissolves
                shape.strokeBorder(Surface.shellRim.opacity(0.55), lineWidth: 0.5)
            }
            .ambientElevation(elevation)
    }
}

public extension View {
    func liquidGlass(
        cornerRadius: CGFloat = Radius.bar,
        tint: Color = .clear,
        isHovered: Bool = false,
        elevation: CGFloat = 1.0,
        tintStrength: CGFloat = 1.0
    ) -> some View {
        modifier(
            LiquidGlassStyle(
                cornerRadius: cornerRadius,
                tint: tint,
                isHovered: isHovered,
                elevation: elevation,
                tintStrength: tintStrength
            )
        )
    }

    func liquidCapsule(cornerRadius: CGFloat = Radius.bar, isHovered: Bool = false) -> some View {
        modifier(LiquidGlassStyle(cornerRadius: cornerRadius, tint: .clear, isHovered: isHovered))
    }
}
