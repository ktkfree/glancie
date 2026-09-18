import AppKit
import SwiftUI

/// Hosts the menu bar dropdown in a borderless `NSPanel` rather than an
/// `NSPopover`, which removes the speech-bubble tail and lets the shell carry its
/// own corner radius, material and shadow stack.
///
/// The window tracks the SwiftUI content's reported size, so drilling into a
/// provider or opening settings resizes the dropdown instead of leaving dead
/// space below short screens.
@MainActor
public final class MenuBarPanelController: NSObject, NSWindowDelegate {
    public static let shared = MenuBarPanelController()

    /// Gap between the status item and the dropdown's visual top edge.
    private static let anchorGap: CGFloat = 5
    /// How far the panel rises while fading in.
    private static let revealLift: CGFloat = 7

    private var panel: NSPanel?
    private var globalClickMonitor: Any?
    private var localEventMonitor: Any?

    /// Screen rect of the status item, kept so the dropdown can re-anchor itself
    /// after a content resize without waiting for another click.
    private var anchorRect: NSRect = .zero
    private var contentSize: CGSize = CGSize(width: Metric.menuWidth + Metric.menuBleed * 2, height: 320)
    /// True during the reveal, while SwiftUI is still settling on the root screen's size.
    private var isSettlingPresentation: Bool = false

    public private(set) var isVisible: Bool = false

    private override init() {
        super.init()
    }

    // MARK: - Presentation

    public func toggle(relativeTo button: NSStatusBarButton) {
        if isVisible {
            hide()
        } else {
            show(relativeTo: button)
        }
    }

    public func show(relativeTo button: NSStatusBarButton) {
        ensurePanelCreated()
        guard let panel else { return }

        if let buttonWindow = button.window {
            anchorRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        }

        MenuBarNavigator.shared.reset()

        let target = anchoredFrame(for: contentSize)
        panel.setFrame(target.offsetBy(dx: 0, dy: Self.revealLift), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        isVisible = true
        isSettlingPresentation = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1.0
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            self.isSettlingPresentation = false
        }

        startEventMonitoring(for: button)
        SoundEffectsEngine.shared.playSelectionFeedback()

        // Opening the menu is a request to see the current figures, not the ones
        // the last poll happened to land on.
        Task { await ProviderManager.shared.refreshOnDemand(ProviderManager.shared.activeProviders, trigger: .userAction) }
    }

    public func hide() {
        guard let panel, isVisible else { return }

        stopEventMonitoring()
        isVisible = false
        isSettlingPresentation = false

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.13
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            Task { @MainActor in
                guard !self.isVisible else { return }
                panel.orderOut(nil)
                MenuBarNavigator.shared.reset()
            }
        })
    }

    // MARK: - Sizing

    /// Called from SwiftUI whenever the dropdown's laid-out size changes.
    public func updateContentSize(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        guard abs(size.width - contentSize.width) > 0.5 || abs(size.height - contentSize.height) > 0.5 else { return }

        contentSize = size
        guard let panel, isVisible else { return }

        let target = anchoredFrame(for: size)

        // Reopening after a drill-down relayouts back to the root a beat after the
        // reveal starts. Animating that would show the dropdown springing to a
        // second height right after opening, so the settling pass is instant.
        if isSettlingPresentation {
            panel.setFrame(target, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().setFrame(target, display: true)
        }
    }

    /// Places the panel so its *visual* top edge — inset from the window edge by
    /// the shadow bleed — sits just under the status item, and its visual body
    /// stays inside the screen.
    private func anchoredFrame(for size: CGSize) -> NSRect {
        let screen = screenForAnchor()
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let bleed = Metric.menuBleed

        let anchorX = anchorRect.isEmpty ? visible.midX : anchorRect.midX
        let anchorTop = anchorRect.isEmpty ? visible.maxY : anchorRect.minY

        var originX = anchorX - size.width / 2.0
        let maxY = anchorTop - Self.anchorGap + bleed
        var originY = maxY - size.height

        // Clamp on the visual edges, not the window edges, so the bleed does not
        // push the dropdown visibly away from the screen boundary.
        let minVisualX = visible.minX + 8
        let maxVisualX = visible.maxX - 8
        if originX + bleed < minVisualX {
            originX = minVisualX - bleed
        } else if originX + size.width - bleed > maxVisualX {
            originX = maxVisualX - size.width + bleed
        }

        let minVisualY = visible.minY + 8
        if originY + bleed < minVisualY {
            originY = minVisualY - bleed
        }

        return NSRect(x: originX.rounded(), y: originY.rounded(), width: size.width, height: size.height)
    }

    private func screenForAnchor() -> NSScreen? {
        if !anchorRect.isEmpty {
            if let match = NSScreen.screens.first(where: { $0.frame.intersects(anchorRect) }) {
                return match
            }
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    // MARK: - Panel

    private func ensurePanelCreated() {
        guard panel == nil else { return }

        let hosting = NSHostingView(rootView: MenuBarPanelHostView())
        hosting.translatesAutoresizingMaskIntoConstraints = true

        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        newPanel.level = .popUpMenu
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        // The elevation stack is composited in SwiftUI. A window shadow is derived
        // from content alpha and lags a frame behind every resize on a translucent
        // panel, which shows up as a shadow ghost during the drill-down animation.
        newPanel.hasShadow = false
        newPanel.isMovableByWindowBackground = false
        newPanel.hidesOnDeactivate = false
        newPanel.isReleasedWhenClosed = false
        newPanel.becomesKeyOnlyIfNeeded = true
        newPanel.animationBehavior = .none
        newPanel.contentView = hosting
        newPanel.delegate = self

        self.panel = newPanel
    }

    /// Visual bounds of the dropdown, excluding the transparent shadow bleed.
    private var visualFrame: NSRect {
        guard let panel else { return .zero }
        return panel.frame.insetBy(dx: Metric.menuBleed, dy: Metric.menuBleed)
    }

    // MARK: - Event monitoring

    private func startEventMonitoring(for button: NSStatusBarButton) {
        stopEventMonitoring()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown {
                return self.handleKeyDown(event)
            }

            let point = NSEvent.mouseLocation
            let hitPanel = self.visualFrame.contains(point)
            let hitButton = button.window?.frame.contains(point) ?? false
            if !hitPanel && !hitButton {
                self.hide()
            }
            return event
        }
    }

    /// Commands advertised by the dropdown's shortcut labels. The panel is
    /// non-activating, so SwiftUI's `.keyboardShortcut` never fires here and the
    /// bindings have to be resolved from the event stream instead.
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { // ESC
            hide()
            return nil
        }

        guard event.modifierFlags.contains(.command) else { return event }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "r":
            SoundEffectsEngine.shared.playImpactFeedback()
            Task { await ProviderManager.shared.refreshAll(forceSync: true) }
            return nil
        case ",":
            MenuBarNavigator.shared.push(.settings)
            return nil
        case "q":
            NSApplication.shared.terminate(nil)
            return nil
        case "w":
            hide()
            return nil
        default:
            return event
        }
    }

    private func stopEventMonitoring() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
}

/// Bridges the SwiftUI content's reported size back to the panel controller.
private struct MenuBarPanelHostView: View {
    /// Observed at the root so a language change re-renders the whole menu.
    /// Child views are structs rebuilt when this body runs, so none of them has
    /// to observe it individually.
    @ObservedObject private var localization = Localization.shared

    var body: some View {
        MenuBarPopoverView()
            .onPreferenceChange(MenuContentSizeKey.self) { size in
                MainActor.assumeIsolated {
                    MenuBarPanelController.shared.updateContentSize(size)
                }
            }
    }
}
