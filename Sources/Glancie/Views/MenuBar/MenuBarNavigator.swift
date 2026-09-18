import SwiftUI

/// Navigation destinations inside the menu bar dropdown.
public enum MenuBarScreen: Equatable {
    case overview
    case providerDetail(AIProviderType)
    case settings
    case about
}

/// Owns which dropdown screen is showing and which way the last move went.
///
/// Lives outside the view so the panel controller can drive it too: keyboard
/// shortcuts push screens, and dismissing the panel rewinds to the root so the
/// menu never reopens halfway down a drill-down.
@MainActor
public final class MenuBarNavigator: ObservableObject {
    public static let shared = MenuBarNavigator()

    @Published public private(set) var screen: MenuBarScreen = .overview
    /// Drives the direction of the push transition.
    @Published public private(set) var isForward: Bool = true

    public init() {}

    public func push(_ destination: MenuBarScreen) {
        guard destination != screen else { return }
        isForward = true
        withAnimation(JellySprings.popover) { screen = destination }
    }

    public func popToRoot() {
        guard screen != .overview else { return }
        isForward = false
        withAnimation(JellySprings.popover) { screen = .overview }
    }

    /// Rewinds without animation, for when the panel is not on screen.
    public func reset() {
        isForward = true
        screen = .overview
    }
}

/// Horizontal push transition: a short slide plus a fade.
///
/// Deliberately a 16pt render offset rather than `.move(edge:)`, which travels
/// the full view width — the panel window is resizing to the new screen's height
/// at the same time, and a full-width slide against a resizing window reads as a
/// tear rather than a push.
struct PushOffsetEffect: ViewModifier {
    var dx: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: dx)
            .opacity(opacity)
    }
}

extension AnyTransition {
    static func menuPush(forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: PushOffsetEffect(dx: forward ? 18 : -18, opacity: 0),
                identity: PushOffsetEffect(dx: 0, opacity: 1)
            ),
            removal: .modifier(
                active: PushOffsetEffect(dx: forward ? -18 : 18, opacity: 0),
                identity: PushOffsetEffect(dx: 0, opacity: 1)
            )
        )
    }
}
