import AppKit
import SwiftUI
import Combine

/// Lifecycle controller for the Floating NSPanel and mouse drag interactions
@MainActor
public final class FloatingPanelController: NSObject, NSWindowDelegate, ObservableObject {
    public static let shared = FloatingPanelController()
    
    public private(set) var panel: FloatingPanel?
    public private(set) var isDragging: Bool = false
    public private(set) var hasDraggedRecently: Bool = false
    public var isCatDragging: Bool = false
    public var isHoveringCat: Bool = false
    @Published public var opensUpward: Bool = false
    
    /// Exact resting frame of the bar (used to ensure 100% stable anchor when opening/closing popover)
    public private(set) var restingBarFrame: NSRect = .zero
    
    /// Pointer position at the moment of the press, in the panel's coordinate
    /// system. A fixed reference only until the window itself starts moving.
    private var pressLocationInWindow: NSPoint = .zero
    private var dragAnchor: PanelDragAnchor?
    private var pendingContentSize: CGSize?
    private var hasMovedPastThreshold: Bool = false
    /// Travel (points) required before a press turns into a window drag. Wide
    /// enough to absorb the residual motion of a press made mid-swipe, so a click
    /// that lands while the pointer is still decelerating stays a click.
    private let dragThreshold: CGFloat = 7.0
    
    private var isMouseDownInBar: Bool = false
    
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    
    /// Top band of the window that behaves as the draggable bar
    private let barHeight: CGFloat = Metric.barBand
    /// The same band measured against the window that is actually on screen: the
    /// pixel cat reserves a strip above the bar, which pushes the bar that much
    /// further from the window's top edge. Without it the lower part of the
    /// visible bar falls outside the band and cannot be grabbed.
    private var barBandHeight: CGFloat {
        barHeight + (GlanciePreferences.shared.pixelCatEnabled ? Metric.pixelCatBand : 0)
    }
    private var currentPanelWidth: CGFloat = Metric.panelWidth

    /// Where the very first measured layout has to land, decided before SwiftUI
    /// has laid anything out and consumed by the first `updateContentSize`.
    /// `nil` once the window's size is the one SwiftUI actually reported.
    private var pendingInitialPlacement: InitialPlacement?
    private var revealWorkItem: DispatchWorkItem?
    private var revealDeadline: DispatchTime?
    /// How long the frame has to hold still before the bar is shown.
    static let revealSettleWindow: TimeInterval = 0.14
    /// Longest the bar may stay hidden waiting for that, measured from `show()`.
    static let revealHardDeadline: TimeInterval = 0.6

    /// The window's first frame is always a guess — it is created before SwiftUI
    /// can measure the bar. These say what that guess must be corrected *to*,
    /// which is never "re-centred around the guess".
    enum InitialPlacement {
        /// The exact frame the bar was parked at, position and size.
        case restored(NSRect)
        /// Preferences from a build that saved the position but not the size.
        case restoredOrigin(NSPoint)
        /// Nothing saved: centre it under the menu bar at its measured width.
        case topCenter
    }

    private override init() {
        super.init()
    }
    
    public func show() {
        if panel == nil {
            setupPanel()
            setupObservers()
        }
        panel?.orderFrontRegardless()
        scheduleRevealFallback()
    }
    
    public func hide() {
        panel?.orderOut(nil)
    }
    
    public func toggle() {
        if let panel = panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }
    
    private func setupPanel() {
        let prefs = GlanciePreferences.shared
        let savedOrigin = NSPoint(x: prefs.panelOriginX, y: prefs.panelOriginY)
        let savedSize = NSSize(width: prefs.panelWidth, height: prefs.panelHeight)
        let hasSavedOrigin = prefs.panelOriginX >= 0 && prefs.panelOriginY >= 0
        let hasSavedSize = savedSize.width > 10 && savedSize.height > 10

        let initialRect: NSRect
        if hasSavedOrigin, hasSavedSize,
           NSScreen.screens.contains(where: { $0.visibleFrame.intersects(NSRect(origin: savedOrigin, size: savedSize)) }) {
            // Born at the size it really had: the first measured layout then
            // agrees with the window and nothing moves.
            initialRect = NSRect(origin: savedOrigin, size: savedSize)
            pendingInitialPlacement = .restored(initialRect)
        } else if hasSavedOrigin,
                  NSScreen.screens.contains(where: { $0.visibleFrame.intersects(NSRect(origin: savedOrigin, size: NSSize(width: Metric.panelWidth, height: barHeight))) }) {
            initialRect = NSRect(origin: savedOrigin, size: NSSize(width: Metric.panelWidth, height: barHeight))
            pendingInitialPlacement = .restoredOrigin(savedOrigin)
        } else {
            let screen = NSScreen.main ?? NSScreen.screens.first
            let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            initialRect = NSRect(
                x: screenFrame.midX - (Metric.panelWidth / 2.0),
                y: screenFrame.maxY - barHeight - 4,
                width: Metric.panelWidth,
                height: barHeight
            )
            pendingInitialPlacement = .topCenter
        }

        let panel = FloatingPanel(contentRect: initialRect)
        
        let hostingView = NSHostingView(rootView: MultiProviderBarView())
        // No hosting constraints of its own, so nothing resizes the panel behind
        // this controller's back and leaves restingBarFrame at an older height.
        // (It does not make the window's size ours: the hosting view still writes
        // the laid-out content size back — see `updateContentSize`.)
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.delegate = self
        self.panel = panel
        self.currentPanelWidth = initialRect.width
        self.restingBarFrame = initialRect

        // Whatever correction the first measurement makes, it happens off
        // screen: a guessed frame is never shown, so there is no hop to see.
        panel.alphaValue = 0
        
        setupMonitors()
    }

    /// Shows the panel once its frame has stopped changing.
    ///
    /// Launch resolves in two steps that are both legitimate — the window is
    /// created before SwiftUI can measure the bar, and the provider list can
    /// still narrow once the scanner answers — and showing the bar between them
    /// is what put the sideways shuffle in front of the user. So the first paint
    /// waits out a short settle window, with a hard deadline so a layout that
    /// never arrives can never leave the bar invisible.
    /// A frame just settled: show the bar unless another layout arrives first.
    private func requestReveal() {
        armReveal(at: min(.now() + Self.revealSettleWindow, revealHardDeadline()))
    }

    /// Nothing has been measured yet: hold the bar until the deadline, so a slow
    /// first layout is still waited for rather than shown after it.
    private func scheduleRevealFallback() {
        armReveal(at: revealHardDeadline())
    }

    private func revealHardDeadline() -> DispatchTime {
        let deadline = revealDeadline ?? (.now() + Self.revealHardDeadline)
        revealDeadline = deadline
        return deadline
    }

    private func armReveal(at when: DispatchTime) {
        guard let panel = panel, panel.alphaValue < 1 else { return }
        revealWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.revealPanel() }
        }
        revealWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: when, execute: work)
    }

    private func revealPanel() {
        revealWorkItem?.cancel()
        revealWorkItem = nil
        revealDeadline = nil
        guard let panel = panel, panel.alphaValue < 1 else { return }
        panel.alphaValue = 1
    }
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, let panel = self.panel else { return }
                let clamped = ScreenPlacementEngine.shared.clampToScreens(frame: self.restingBarFrame)
                if clamped.origin != self.restingBarFrame.origin {
                    self.restingBarFrame.origin = clamped.origin
                    panel.setFrameOrigin(clamped.origin)
                    self.persistRestingFrame()
                }
            }
            .store(in: &cancellables)
    }
    
    /// Evaluate available room and decide whether popover should open upward or downward.
    /// MUST only be calculated when popover is closed or upon window drag to prevent layout thrashing.
    public func checkPlacementDirection() {
        guard let panel = panel else { return }
        // Lock direction while popover is active to guarantee 100% stable return anchor
        guard !isDragging, ProviderManager.shared.selectedProvider == nil else { return }
        
        let anchorOrigin = (restingBarFrame != .zero) ? restingBarFrame.origin : panel.frame.origin
        let screen = ScreenPlacementEngine.shared.screen(for: anchorOrigin)
        let screenVisibleFrame = screen.visibleFrame
        
        // Calculate remaining room below the resting bar position
        let spaceBelow = anchorOrigin.y - screenVisibleFrame.minY
        let requiredCardHeight: CGFloat = 260.0
        
        let shouldOpenUpward = spaceBelow < requiredCardHeight
        if shouldOpenUpward != opensUpward {
            opensUpward = shouldOpenUpward
        }
    }

    /// Resize the panel to the size SwiftUI actually laid out, keeping the bar pinned
    /// (top pinned for downward popover, bottom pinned for upward popover) and centered horizontally.
    ///
    /// **Architecture invariant**: `restingBarFrame` stores the bar-only anchor (origin + bar size).
    /// It is ONLY updated when the panel is truly at bar-only size (no detail card visible).
    /// During popover close, SwiftUI may report *intermediate* sizes before settling to bar-only,
    /// because `selectedProvider` is set to nil (Closed State) before layout completes.
    /// Those intermediate passes must NOT touch `restingBarFrame` — they use the Open State
    /// expansion logic against the frozen anchor instead.
    public func updateContentSize(_ size: CGSize) {
        guard let panel = panel, size.width > 10, size.height > 10 else { return }
        
        // Layout callbacks must not resize, re-anchor or clamp a moving window.
        if isDragging {
            pendingContentSize = size
            return
        }

        // SwiftUI, not this method, has the last word on the window's size: a few
        // milliseconds after every `setFrame` the hosting view pushes the laid-out
        // content size back onto the window, truncated to whole points. The bar's
        // ideal width lands on a half point (the 0.5pt hairline divider), so
        // asking for `ceil` asked for a width the window would never keep — the
        // "already the right size" early-out below could then never fire, every
        // layout pass resized the window again, and `restingBarFrame` stayed
        // permanently a point wider than the bar actually on screen.
        let targetWidth = size.width.rounded(.down)
        let targetHeight = size.height.rounded(.down)
        let currentFrame = panel.frame
        self.currentPanelWidth = targetWidth
        let isPopoverOpen = (ProviderManager.shared.selectedProvider != nil)
        
        // Determine whether this size represents the bar-only (resting) state.
        // The bar-only height is barHeight (Metric.barBand) or slightly larger when pixelCat
        // adds padding. We use a generous threshold: anything more than 2× barHeight is NOT
        // bar-only — it contains the detail card (or a mid-close intermediate layout).
        let isBarOnlySize = (targetHeight <= barHeight * 2.2)

        // A sub-point difference is never a real size change — the bar's width
        // moves a whole provider chip at a time — but it is exactly what a
        // rounding disagreement with SwiftUI looks like. Tolerating it is what
        // keeps the two from resizing the window back and forth forever.
        guard abs(currentFrame.width - targetWidth) > Self.sizeTolerance
                || abs(currentFrame.height - targetHeight) > Self.sizeTolerance else {
            // A matching window size does not guarantee the saved anchor is current.
            if !isPopoverOpen && isBarOnlySize {
                pendingInitialPlacement = nil
                restingBarFrame = currentFrame
                persistRestingFrame()
                requestReveal()
            }
            return
        }
        
        if !isPopoverOpen && isBarOnlySize {
            // ── True Closed State: bar-only dimensions confirmed ──
            // Safe to update restingBarFrame's origin + size.
            checkPlacementDirection()

            let targetSize = NSSize(width: targetWidth, height: targetHeight)
            let anchorFrame: NSRect
            let horizontalPin: PanelHorizontalPin

            if let placement = pendingInitialPlacement {
                // First measured layout. The frame the window was created with
                // was a guess, so re-centring around its midX would move the bar
                // by half the error — the sideways hop (sometimes two of them,
                // as providers resolved) that greeted every launch. Anchor on
                // the position the bar was actually parked at instead.
                pendingInitialPlacement = nil
                anchorFrame = Self.initialAnchorFrame(
                    for: placement,
                    size: targetSize,
                    screen: NSScreen.main ?? NSScreen.screens.first
                )
                horizontalPin = .leading
            } else if restingBarFrame != .zero {
                anchorFrame = restingBarFrame
                horizontalPin = .center
            } else {
                anchorFrame = currentFrame
                horizontalPin = .center
            }

            let candidateRect = PanelReanchor.frame(
                anchor: anchorFrame,
                size: targetSize,
                opensUpward: opensUpward,
                horizontal: horizontalPin
            )
            let clamped = ScreenPlacementEngine.shared.clampToScreens(frame: candidateRect)
            
            restingBarFrame = clamped
            panel.setFrame(restingBarFrame, display: false, animate: false)
            persistRestingFrame()
            requestReveal()
        } else {
            // ── Expanded / Transitional State ──
            // Either popover is open, or selectedProvider is nil but SwiftUI hasn't
            // finished shrinking to bar-only yet (intermediate layout).
            // In both cases: expand from the FROZEN restingBarFrame anchor.
            // Never touch restingBarFrame here.
            let candidateRect = PanelReanchor.frame(
                anchor: restingBarFrame,
                size: NSSize(width: targetWidth, height: targetHeight),
                opensUpward: opensUpward,
                horizontal: .center
            )
            let clamped = ScreenPlacementEngine.shared.clampToScreens(frame: candidateRect)
            panel.setFrame(clamped, display: false, animate: false)
            // A card can only be open once the bar has been seen, but never let a
            // layout leave the window invisible if it somehow gets here first.
            requestReveal()
        }
    }
    
    public func updateContentHeight(_ height: CGFloat) {
        updateContentSize(CGSize(width: currentPanelWidth, height: height))
    }

    /// Tolerated disagreement between the window's size and the measured one.
    static let sizeTolerance: CGFloat = 1.0

    /// The frame the first measured layout has to produce, for each way the
    /// window's guessed starting frame can have come about.
    static func initialAnchorFrame(
        for placement: InitialPlacement,
        size: NSSize,
        screen: NSScreen?
    ) -> NSRect {
        switch placement {
        case .restored(let saved):
            // Position *and* size are known, so a changed height (the pixel cat
            // toggled between launches) still keeps the edge the bar is pinned to.
            return saved
        case .restoredOrigin(let origin):
            // Older preferences: the corner is all that was recorded.
            return NSRect(origin: origin, size: size)
        case .topCenter:
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            return NSRect(
                x: (visible.midX - size.width / 2.0).rounded(),
                y: visible.maxY - size.height - 4,
                width: size.width,
                height: size.height
            )
        }
    }

    /// Records where the bar is resting so the next launch can recreate the
    /// window at that exact frame instead of guessing one.
    private func persistRestingFrame() {
        let prefs = GlanciePreferences.shared
        let frame = restingBarFrame
        // Written from inside a layout callback, so only when something actually
        // changed: an @AppStorage write publishes, and republishing the same
        // numbers buys a re-render per layout pass for nothing.
        guard prefs.panelOriginX != Double(frame.origin.x)
                || prefs.panelOriginY != Double(frame.origin.y)
                || prefs.panelWidth != Double(frame.width)
                || prefs.panelHeight != Double(frame.height) else { return }
        prefs.panelOriginX = Double(frame.origin.x)
        prefs.panelOriginY = Double(frame.origin.y)
        prefs.panelWidth = Double(frame.width)
        prefs.panelHeight = Double(frame.height)
    }
    
    private func closePopoverIfOpen() {
        if ProviderManager.shared.selectedProvider != nil {
            ProviderManager.shared.selectedProvider = nil
        }
    }
    
    private func isLocationInsideBar(_ loc: NSPoint, in panel: NSPanel) -> Bool {
        let band = self.barBandHeight
        let isYInside = opensUpward
            ? (loc.y <= band)
            : (loc.y >= (panel.frame.height - band))
        return isYInside && loc.x >= 0 && loc.x <= panel.frame.width
    }
    
    private func isLocationInsideCard(_ loc: NSPoint, in panel: NSPanel) -> Bool {
        guard ProviderManager.shared.selectedProvider != nil else { return false }
        
        let cardWidth = Metric.detailWidth
        let cardMinX = (panel.frame.width - cardWidth) / 2.0
        let cardMaxX = cardMinX + cardWidth
        
        let cardMinY: CGFloat
        let cardMaxY: CGFloat
        
        if opensUpward {
            cardMinY = barBandHeight
            cardMaxY = panel.frame.height
        } else {
            cardMinY = 0
            cardMaxY = panel.frame.height - barBandHeight
        }
        
        return loc.x >= cardMinX && loc.x <= cardMaxX && loc.y >= cardMinY && loc.y <= cardMaxY
    }
    
    private func setupMonitors() {
        // 1. Global Monitor: Click outside the app window closes open popover
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopoverIfOpen()
            }
        }
        
        // 2. Local Monitor: Dragging detection & inside/outside panel dismissal
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel else { return event }
            
            // The event's own coordinates, never a live pointer query: by the time
            // this block runs the pointer may have travelled hundreds of points past
            // where the click actually landed (measured: 50pt on an idle main thread,
            // 250pt when the click wakes a busy one). A live query therefore hit-tests
            // a position the user never clicked, and the press is dropped — which is
            // why sweeping in from another window and grabbing the bar in one motion
            // used to do nothing on the first try.
            let mouseLocationInWindow = (event.window == panel)
                ? event.locationInWindow
                : panel.mouseLocationOutsideOfEventStream
            let isInsideBar = self.isLocationInsideBar(mouseLocationInWindow, in: panel)
            let isInsideCard = self.isLocationInsideCard(mouseLocationInWindow, in: panel)
            
            switch event.type {
            case .leftMouseDown:
                if self.isHoveringCat || self.isCatDragging {
                    return event
                }
                if event.window == panel {
                    if isInsideBar {
                        // Capture resting bar origin without closing popover yet (lets child button clicks proceed!)
                        self.isMouseDownInBar = true
                        self.pressLocationInWindow = mouseLocationInWindow
                        self.dragAnchor = PanelDragAnchor(
                            pointer: panel.convertPoint(toScreen: mouseLocationInWindow),
                            panelFrame: panel.frame,
                            barSize: self.restingBarFrame.size,
                            opensUpward: self.opensUpward,
                            isPopoverOpen: ProviderManager.shared.selectedProvider != nil
                        )
                        self.hasMovedPastThreshold = false
                    } else if isInsideCard {
                        // Click inside the detail popover card: do not close, do not initiate bar drag
                        self.isMouseDownInBar = false
                    } else {
                        // Click on the empty/bleed margin of the panel window outside card and bar -> close popover
                        self.isMouseDownInBar = false
                        self.closePopoverIfOpen()
                    }
                } else {
                    // Clicked on another window within the app -> close popover
                    self.isMouseDownInBar = false
                    self.closePopoverIfOpen()
                }
                
            case .leftMouseDragged:
                // Hover changes during a bar drag must not transfer its ownership.
                if self.isCatDragging {
                    return event
                }
                // Only allow window dragging if the mouse press originated inside the bar
                guard self.isMouseDownInBar else { return event }
                guard event.window == panel else { return event }
                
                if !self.hasMovedPastThreshold {
                    // The window has not moved yet, so the event's window coordinates
                    // measure exactly how far the pointer has travelled since the
                    // press — no queue drift, unlike a live pointer query. That makes
                    // distance alone enough to tell a deliberate drag from the residual
                    // motion of a click made mid-swipe, so there is no hold delay to
                    // swallow the start of a quick drag.
                    let travelled = hypot(
                        mouseLocationInWindow.x - self.pressLocationInWindow.x,
                        mouseLocationInWindow.y - self.pressLocationInWindow.y
                    )
                    guard travelled > self.dragThreshold else { return event }
                    
                    self.hasMovedPastThreshold = true
                    self.isDragging = true
                    self.hasDraggedRecently = true
                    // Wherever the bar is going now outranks wherever it was
                    // parked last session: a first layout still queued behind
                    // this drag must not snap it back to the saved corner.
                    self.pendingInitialPlacement = nil
                    
                    // Collapse around the bar's actual on-screen position. The
                    // expanded card may have been clamped away from its saved anchor.
                    guard let anchor = self.dragAnchor else { return event }
                    self.restingBarFrame = anchor.barFrame
                    let wasPopoverOpen = ProviderManager.shared.selectedProvider != nil
                    self.closePopoverIfOpen()
                    if wasPopoverOpen {
                        panel.setFrame(anchor.barFrame, display: false, animate: false)
                    }
                }

                guard let anchor = self.dragAnchor else { return event }
                // Keep the original grab point, including travel before the drag
                // threshold. Use one live screen sample once the window is moving.
                let newOrigin = anchor.origin(for: NSEvent.mouseLocation)

                panel.setFrameOrigin(newOrigin)
                self.restingBarFrame.origin = newOrigin
                
            case .leftMouseUp:
                self.isMouseDownInBar = false
                
                if self.hasMovedPastThreshold {
                    self.isDragging = false
                    self.hasDraggedRecently = true
                    
                    if let size = self.pendingContentSize {
                        self.pendingContentSize = nil
                        self.updateContentSize(size)
                    }

                    // Safely clamp to current screen and persist location, on whole
                    // pixels: the origin is what gets stored and restored next launch.
                    var clamped = ScreenPlacementEngine.shared.clampToScreens(frame: self.restingBarFrame)
                    clamped.origin = NSPoint(x: clamped.origin.x.rounded(), y: clamped.origin.y.rounded())
                    panel.setFrameOrigin(clamped.origin)
                    self.restingBarFrame.origin = clamped.origin
                    self.persistRestingFrame()
                    self.checkPlacementDirection()
                    
                    // Reset recent drag flag after a small delay to suppress tap actions triggered on mouse up
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        if !self.isDragging {
                            self.hasDraggedRecently = false
                        }
                    }
                } else {
                    self.isDragging = false
                    self.hasDraggedRecently = false
                }
                self.hasMovedPastThreshold = false
                self.dragAnchor = nil
                
            case .rightMouseDown:
                if !isInsideCard {
                    self.closePopoverIfOpen()
                }
                
            default:
                break
            }
            
            return event
        }
    }
    
    deinit {
        if let globalMonitor = globalEventMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor = localEventMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}

/// Which horizontal edge of the old frame survives a resize.
public enum PanelHorizontalPin {
    /// Dynamic-Island growth: the bar breathes around its own centre. What the
    /// bar does for the whole of a session.
    case center
    /// Restoration: the bar reappears where it was parked, so the edge the user
    /// last saw is the edge that stays. Only the first measured layout.
    case leading
}

/// Re-anchoring a frame onto a newly measured size. Pure geometry, so the rule
/// the panel resizes by is testable without a window.
public enum PanelReanchor {
    public static func frame(
        anchor: NSRect,
        size: NSSize,
        opensUpward: Bool,
        horizontal: PanelHorizontalPin
    ) -> NSRect {
        let x: CGFloat
        switch horizontal {
        case .center: x = anchor.midX - size.width / 2.0
        case .leading: x = anchor.minX
        }
        // The bar sits at the window's top when the card opens downward, and at
        // its bottom when the card opens upward. That edge never moves.
        let y = opensUpward ? anchor.minY : (anchor.maxY - size.height)
        // Whole points, because that is what the window will store anyway. An
        // anchor half a point off the window it describes is a centre that walks
        // a little further every time the bar is re-measured.
        return NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }
}

/// Screen-space grab reference, independent of subsequent panel movement or layout.
struct PanelDragAnchor {
    let pointer: NSPoint
    let barFrame: NSRect
    var barOrigin: NSPoint { barFrame.origin }

    init(pointer: NSPoint, panelFrame: NSRect, barSize: NSSize, opensUpward: Bool, isPopoverOpen: Bool) {
        self.pointer = pointer
        if isPopoverOpen {
            self.barFrame = NSRect(
                x: panelFrame.midX - barSize.width / 2,
                y: opensUpward ? panelFrame.minY : panelFrame.maxY - barSize.height,
                width: barSize.width,
                height: barSize.height
            )
        } else {
            // A closed bar must never shrink to a stale cached size on mouse-down.
            self.barFrame = panelFrame
        }
    }

    func origin(for pointer: NSPoint) -> NSPoint {
        NSPoint(
            x: barOrigin.x + pointer.x - self.pointer.x,
            y: barOrigin.y + pointer.y - self.pointer.y
        )
    }
}
