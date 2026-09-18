import AppKit
import SwiftUI
import Combine

/// Manages full-screen dragging for the Pixel Cat companion across all screens so it never gets clipped by window bounds.
@MainActor
public final class PixelCatOverlayController: ObservableObject {
    public static let shared = PixelCatOverlayController()

    public private(set) var overlayPanel: NSPanel?
    private var isDragging: Bool = false
    
    @Published public var isVisible: Bool = false
    @Published public var catScreenPosition: CGPoint = .zero
    @Published public var currentFrame: PixelCatFrame = PixelCatSprites.dangle1
    @Published public var isFacingLeft: Bool = false
    @Published public var jumpOffsetY: CGFloat = 0.0

    private init() {}

    private func setupOverlayIfNeeded() {
        if overlayPanel == nil {
            let screens = NSScreen.screens
            let unionFrame = screens.reduce(CGRect.null) { $0.union($1.frame) }
            let frame = unionFrame.isNull ? (NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)) : unionFrame

            let panel = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating + 20
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false

            panel.contentView = NSHostingView(rootView: PixelCatOverlayContainerView(controller: self))
            self.overlayPanel = panel
        }
    }

    public func startDrag(screenPoint: CGPoint, isFacingLeft: Bool, initialFrame: PixelCatFrame) {
        setupOverlayIfNeeded()
        guard let panel = overlayPanel else { return }

        // Update frame to encompass all screens dynamically
        let screens = NSScreen.screens
        let unionFrame = screens.reduce(CGRect.null) { $0.union($1.frame) }
        let frame = unionFrame.isNull ? (NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)) : unionFrame
        panel.setFrame(frame, display: true)

        self.isDragging = true
        self.isVisible = true
        self.catScreenPosition = screenPoint
        self.isFacingLeft = isFacingLeft
        self.currentFrame = initialFrame
        self.jumpOffsetY = 0.0

        panel.orderFrontRegardless()
    }

    public func updateDrag(screenPoint: CGPoint, dx: CGFloat) {
        guard isDragging else { return }
        self.catScreenPosition = screenPoint
        if dx > 2.0 {
            self.isFacingLeft = false
        } else if dx < -2.0 {
            self.isFacingLeft = true
        }
    }

    public func updateFrame(_ frame: PixelCatFrame) {
        if isDragging || isVisible {
            self.currentFrame = frame
        }
    }

    public func endDrag(targetScreenPoint: CGPoint, completion: @escaping () -> Void) {
        guard isDragging else {
            completion()
            return
        }
        isDragging = false

        SoundEffectsEngine.shared.playSnapSound()

        // Fly from current release position across the screen to target position on the bar
        withAnimation(Animation.interpolatingSpring(stiffness: 240, damping: 16)) {
            self.catScreenPosition = targetScreenPoint
            self.jumpOffsetY = -4.0
        }

        Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            await MainActor.run {
                withAnimation(JellySprings.layout) {
                    self.jumpOffsetY = 0.0
                }
            }
            try? await Task.sleep(nanoseconds: 60_000_000)
            await MainActor.run {
                self.isVisible = false
                self.overlayPanel?.orderOut(nil)
                completion()
            }
        }
    }
}

/// SwiftUI View rendered inside the fullscreen overlay panel
public struct PixelCatOverlayContainerView: View {
    @ObservedObject public var controller: PixelCatOverlayController
    @ObservedObject private var preferences = GlanciePreferences.shared
    @ObservedObject private var localization = Localization.shared

    public var body: some View {
        GeometryReader { geo in
            if controller.isVisible {
                let pixelSize: CGFloat = 1.35
                let spriteWidth: CGFloat = 16 * pixelSize
                let spriteHeight: CGFloat = 16 * pixelSize
                let palette = preferences.pixelCatBreed.palette

                // Convert AppKit screen coordinate (bottom-left origin) to SwiftUI view coordinate (top-left origin)
                let panelFrame = controller.overlayPanel?.frame ?? NSRect(origin: .zero, size: geo.size)
                let swiftUIX = controller.catScreenPosition.x - panelFrame.minX
                let swiftUIY = panelFrame.maxY - controller.catScreenPosition.y

                ZStack(alignment: .bottom) {
                    PixelArtCanvas(
                        frameData: controller.currentFrame,
                        palette: palette,
                        pixelSize: pixelSize
                    )
                    .scaleEffect(x: controller.isFacingLeft ? -1.0 : 1.0, y: 1.0)
                    .offset(y: controller.jumpOffsetY)
                }
                .frame(width: max(32, spriteWidth), height: max(26, spriteHeight))
                .position(x: swiftUIX, y: swiftUIY)
            }
        }
        .ignoresSafeArea()
    }
}
