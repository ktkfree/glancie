import SwiftUI

/// iOS sheet-grabber affordance. Reads as "this surface moves" without adding a
/// competing icon to the bar; brightens and grows slightly on hover.
public struct GrabberHandle: View {
    public var isActive: Bool

    public init(isActive: Bool = false) {
        self.isActive = isActive
    }

    public var body: some View {
        Capsule(style: .continuous)
            .fill(Color.primary.opacity(isActive ? 0.42 : 0.22))
            .frame(width: 3, height: isActive ? 15 : 12)
            .animation(JellySprings.hover, value: isActive)
            .accessibilityHidden(true)
    }
}
