import SwiftUI
import Combine
import AppKit

public enum CatAction: Equatable {
    case walking
    case idle
    case sitting
    case grooming
    case layingDown
    case sleeping
    case stretching
    case happy
    case dangling
}

@MainActor
public final class PixelCatEngine: ObservableObject {
    @Published public var positionX: CGFloat = 60.0
    @Published public var isFacingLeft: Bool = false
    @Published public var currentAction: CatAction = .walking
    @Published public var currentFrame: PixelCatFrame = PixelCatSprites.walk1
    @Published public var jumpOffsetY: CGFloat = 0.0
    @Published public var dragOffset: CGSize = .zero
    @Published public var isBeingHeld: Bool = false
    @Published public var zBubbleOpacity: Double = 0.0
    @Published public var zBubbleOffset: CGFloat = 0.0
    @Published public var heartOpacity: Double = 0.0
    @Published public var heartOffset: CGFloat = 0.0

    private var animationTimer: AnyCancellable?
    private var aiTimer: AnyCancellable?
    private var frameToggle: Bool = false
    private var subFrameIndex: Int = 0
    private var dangleIndex: Int = 0
    private var actionDuration: TimeInterval = 0.0
    
    // Bounds of movement on top of the tab bar (dynamically matched to actual rendered bar width)
    public var minX: CGFloat = 14.0
    public var maxX: CGFloat = 100.0
    
    /// Whether the view hosting the cat is on screen right now.
    private var isPresented: Bool = false
    private var occlusionObserver: NSObjectProtocol?

    /// Deliberately starts nothing.
    ///
    /// The loops used to start in `init`, which meant a 0.12s timer publishing
    /// `@Published` changes — and so a SwiftUI re-render eight times a second —
    /// for the entire life of the app: while the cat was switched off in
    /// settings, while the bar was hidden behind a full-screen window, while the
    /// display was asleep. An idle menu bar app has no business animating.
    public init() {}

    /// The hosting view appeared. Paired with `viewDisappeared()`.
    public func viewAppeared() {
        isPresented = true
        observeOcclusion()
        syncLoops()
    }

    public func viewDisappeared() {
        isPresented = false
        syncLoops()
    }

    private func observeOcclusion() {
        guard occlusionObserver == nil else { return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncLoops() }
        }
    }

    /// Runs the loops only while something can actually see them.
    private func syncLoops() {
        let visible = NSApp?.occlusionState.contains(.visible) ?? true
        if isPresented && visible {
            startLoops()
        } else {
            stopLoops()
        }
    }

    public func stopLoops() {
        animationTimer?.cancel()
        animationTimer = nil
        aiTimer?.cancel()
        aiTimer = nil
    }
    
    public func updateBounds(minX: CGFloat, maxX: CGFloat) {
        self.minX = minX
        self.maxX = max(minX + 30.0, maxX)
        
        // Only clamp position if outside bounds, and do it with smooth animation
        if positionX > self.maxX {
            withAnimation(.easeOut(duration: 0.2)) {
                positionX = self.maxX
            }
            isFacingLeft = true
        } else if positionX < self.minX {
            withAnimation(.easeOut(duration: 0.2)) {
                positionX = self.minX
            }
            isFacingLeft = false
        }
    }
    
    deinit {
        animationTimer?.cancel()
        aiTimer?.cancel()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }
    
    // MARK: - Game Loop & AI
    
    public func startLoops() {
        guard animationTimer == nil else { return }

        // Continuous animation frame tick (~8.3 fps sprite toggle, with smooth linear 60/120fps translation)
        animationTimer = Timer.publish(every: 0.12, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tickFrame()
            }
        
        // AI State decision tick (~every 1.0 second)
        aiTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tickAI()
            }
    }
    
    private func tickFrame() {
        frameToggle.toggle()
        subFrameIndex = (subFrameIndex + 1) % 4
        
        switch currentAction {
        case .walking:
            let step: CGFloat = isFacingLeft ? -3.0 : 3.0
            let newX = positionX + step
            
            if newX <= minX {
                withAnimation(.linear(duration: 0.12)) {
                    positionX = minX
                }
                isFacingLeft = false
                handleBorderContact()
            } else if newX >= maxX {
                withAnimation(.linear(duration: 0.12)) {
                    positionX = maxX
                }
                isFacingLeft = true
                handleBorderContact()
            } else {
                withAnimation(.linear(duration: 0.12)) {
                    positionX = newX
                }
            }
            
            currentFrame = frameToggle ? PixelCatSprites.walk1 : PixelCatSprites.walk2
            
        case .idle:
            currentFrame = (subFrameIndex < 2) ? PixelCatSprites.idle1 : PixelCatSprites.idle2
            
        case .sitting:
            currentFrame = (subFrameIndex == 3) ? PixelCatSprites.sit2 : PixelCatSprites.sit1
            
        case .grooming:
            currentFrame = frameToggle ? PixelCatSprites.wash1 : PixelCatSprites.wash2
            
        case .layingDown:
            currentFrame = PixelCatSprites.loaf
            
        case .sleeping:
            currentFrame = (subFrameIndex < 2) ? PixelCatSprites.sleep1 : PixelCatSprites.sleep2
            animateZBubble()
            
        case .stretching:
            currentFrame = PixelCatSprites.stretch
            
        case .happy:
            currentFrame = PixelCatSprites.happy
            
        case .dangling:
            dangleIndex = (dangleIndex + 1) % 3
            if dangleIndex == 0 {
                currentFrame = PixelCatSprites.dangle1
            } else if dangleIndex == 1 {
                currentFrame = PixelCatSprites.dangle2
            } else {
                currentFrame = PixelCatSprites.dangle3
            }
            PixelCatOverlayController.shared.updateFrame(currentFrame)
        }
    }
    
    private func tickAI() {
        guard currentAction != .happy && currentAction != .dangling && !isBeingHeld else { return }
        
        actionDuration += 1.0
        
        // State transition thresholds
        switch currentAction {
        case .walking:
            if actionDuration >= Double.random(in: 4.5...10.0) {
                // Decide what to do after walking
                let roll = Int.random(in: 0...100)
                if roll < 35 {
                    setAction(.sitting)
                } else if roll < 65 {
                    setAction(.idle)
                } else {
                    // Turn around and keep walking
                    isFacingLeft.toggle()
                    actionDuration = 0
                }
            }
            
        case .idle:
            if actionDuration >= Double.random(in: 2.0...4.5) {
                let roll = Int.random(in: 0...100)
                if roll < 55 {
                    startWalking(randomizeDirection: true)
                } else if roll < 80 {
                    setAction(.sitting)
                } else {
                    setAction(.stretching)
                }
            }
            
        case .sitting:
            if actionDuration >= Double.random(in: 3.5...7.0) {
                let roll = Int.random(in: 0...100)
                if roll < 35 {
                    setAction(.grooming)
                } else if roll < 70 {
                    startWalking(randomizeDirection: true)
                } else if roll < 85 {
                    setAction(.layingDown)
                } else {
                    setAction(.sleeping)
                }
            }
            
        case .grooming:
            if actionDuration >= Double.random(in: 3.0...5.5) {
                let roll = Int.random(in: 0...100)
                if roll < 45 {
                    setAction(.sitting)
                } else {
                    startWalking(randomizeDirection: true)
                }
            }
            
        case .layingDown:
            if actionDuration >= Double.random(in: 5.0...10.0) {
                if Bool.random() {
                    setAction(.sleeping)
                } else {
                    setAction(.sitting)
                }
            }
            
        case .sleeping:
            if actionDuration >= Double.random(in: 8.0...16.0) {
                // Wake up and stretch
                setAction(.stretching)
            }
            
        case .stretching:
            if actionDuration >= 2.0 {
                startWalking(randomizeDirection: true)
            }
            
        case .happy, .dangling:
            break
        }
    }
    
    private func handleBorderContact() {
        actionDuration = 0
        let roll = Int.random(in: 0...100)
        if roll < 70 {
            // 70% chance: Turn around and continue walking smoothly
        } else if roll < 90 {
            setAction(.sitting)
        } else {
            setAction(.idle)
        }
    }
    
    public func setAction(_ action: CatAction) {
        currentAction = action
        actionDuration = 0
        
        if action != .sleeping {
            withAnimation(.easeOut(duration: 0.2)) {
                zBubbleOpacity = 0.0
            }
        }
    }
    
    private func startWalking(randomizeDirection: Bool) {
        if randomizeDirection {
            if positionX <= minX + 20 {
                isFacingLeft = false
            } else if positionX >= maxX - 20 {
                isFacingLeft = true
            } else {
                isFacingLeft = Bool.random()
            }
        }
        setAction(.walking)
    }
    
    // MARK: - Drag & Move Interactions
    
    public func onDragStarted(screenPoint: CGPoint) {
        isBeingHeld = true
        FloatingPanelController.shared.isCatDragging = true
        SoundEffectsEngine.shared.playSelectionFeedback()
        setAction(.dangling)
        
        PixelCatOverlayController.shared.startDrag(
            screenPoint: screenPoint,
            isFacingLeft: isFacingLeft,
            initialFrame: currentFrame
        )
    }
    
    public func onDragChanged(translation: CGSize, screenPoint: CGPoint) {
        if translation.width > 2.0 {
            isFacingLeft = false
        } else if translation.width < -2.0 {
            isFacingLeft = true
        }
        
        PixelCatOverlayController.shared.updateDrag(
            screenPoint: screenPoint,
            dx: translation.width
        )
    }
    
    public func onDragEnded(translation: CGSize, screenPoint: CGPoint, actualBarWidth: CGFloat) {
        let targetLandingX = min(max(positionX + translation.width, minX), maxX)
        
        // Calculate landing position in screen coordinates
        let targetScreenPoint: CGPoint
        if let panel = FloatingPanelController.shared.panel {
            let panelFrame = panel.frame
            let screenX = panelFrame.minX + Metric.panelBleed + 9 + targetLandingX
            let screenY = FloatingPanelController.shared.opensUpward
                ? (panelFrame.minY + Metric.panelBleed + Metric.barHeight - 6)
                : (panelFrame.maxY - Metric.panelBleed - 6)
            targetScreenPoint = CGPoint(x: screenX, y: screenY)
        } else {
            targetScreenPoint = screenPoint
        }
        
        PixelCatOverlayController.shared.endDrag(targetScreenPoint: targetScreenPoint) { [weak self] in
            guard let self = self else { return }
            self.positionX = targetLandingX
            self.isBeingHeld = false
            self.dragOffset = .zero
            self.jumpOffsetY = 0
            FloatingPanelController.shared.isCatDragging = false
            SoundEffectsEngine.shared.playSelectionFeedback()
            self.setAction(.sitting)
        }
    }
    
    // MARK: - User Interactions
    
    /// Triggered when the user hovers over the bar
    public func onBarHover(isHovered: Bool) {
        guard currentAction != .happy && currentAction != .sleeping && currentAction != .dangling else { return }
        
        if isHovered && currentAction == .walking {
            // Cat pauses and looks at the user with curiosity
            setAction(.idle)
        }
    }
    
    /// Triggered when user taps the cat
    public func onCatTapped() {
        guard currentAction != .dangling else { return }
        SoundEffectsEngine.shared.playSnapSound()
        SoundEffectsEngine.shared.playSelectionFeedback()
        
        setAction(.happy)
        
        // Hop animation
        withAnimation(JellySprings.layout) {
            jumpOffsetY = -7.0
            heartOpacity = 1.0
            heartOffset = -14.0
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            await MainActor.run {
                withAnimation(JellySprings.layout) {
                    self.jumpOffsetY = 0.0
                }
            }
            
            try? await Task.sleep(nanoseconds: 700_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    self.heartOpacity = 0.0
                    self.heartOffset = -22.0
                }
                self.setAction(.sitting)
            }
        }
    }
    
    private func animateZBubble() {
        withAnimation(.easeInOut(duration: 0.8)) {
            zBubbleOpacity = 1.0
            zBubbleOffset = -8.0
        }
    }
}
