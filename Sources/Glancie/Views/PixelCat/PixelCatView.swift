import SwiftUI

/// Overlay View that displays the Pixel Cat companion walking and lounging on top of the tab bar
public struct PixelCatView: View {
    @StateObject private var catEngine = PixelCatEngine()
    @ObservedObject private var preferences = GlanciePreferences.shared
    
    public var isBarHovered: Bool = false
    public var barWidth: CGFloat? = nil
    
    public init(isBarHovered: Bool = false, barWidth: CGFloat? = nil) {
        self.isBarHovered = isBarHovered
        self.barWidth = barWidth
    }
    
    public var body: some View {
        if preferences.pixelCatEnabled {
            let spriteWidth: CGFloat = 16 * 1.35
            let effectiveWidth = max(80, barWidth ?? 180)
            
            ZStack(alignment: .leading) {
                catLayer(spriteWidth: spriteWidth)
            }
            .frame(width: effectiveWidth, height: 24, alignment: .leading)
            .clipped()
            .onAppear {
                catEngine.viewAppeared()
                updateBounds(barWidth: effectiveWidth, spriteWidth: spriteWidth)
            }
            .onDisappear {
                catEngine.viewDisappeared()
            }
            .onChange(of: effectiveWidth) { _, newWidth in
                updateBounds(barWidth: newWidth, spriteWidth: spriteWidth)
            }
            .onChange(of: isBarHovered) { _, newValue in
                catEngine.onBarHover(isHovered: newValue)
            }
            .frame(width: effectiveWidth, height: 24)
            .allowsHitTesting(true)
        }
    }
    
    private func updateBounds(barWidth: CGFloat, spriteWidth: CGFloat) {
        guard barWidth > 0 else { return }
        // Left and right padding considering the capsule curve (Radius.bar ≈ 17)
        let minX: CGFloat = 12.0
        let maxX = max(minX + 24.0, barWidth - spriteWidth - 12.0)
        catEngine.updateBounds(minX: minX, maxX: maxX)
    }
    
    @ViewBuilder
    private func catLayer(spriteWidth: CGFloat) -> some View {
        let palette = preferences.pixelCatBreed.palette
        let pixelSize: CGFloat = 1.35
        let spriteHeight: CGFloat = 16 * pixelSize
        
        ZStack(alignment: .bottom) {
            // Tiny contact shadow on the edge of the bar (fades when cat is lifted)
            Ellipse()
                .fill(Color.black.opacity(catEngine.isBeingHeld ? 0.12 : 0.35))
                .frame(
                    width: spriteWidth * (catEngine.isBeingHeld ? 0.5 : 0.8),
                    height: 3.5
                )
                .offset(y: 1.0)
            
            // The Pixel Cat Sprite Canvas
            PixelArtCanvas(
                frameData: catEngine.currentFrame,
                palette: palette,
                pixelSize: pixelSize
            )
            .scaleEffect(x: catEngine.isFacingLeft ? -1.0 : 1.0, y: 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: catEngine.isFacingLeft)
            .offset(y: catEngine.jumpOffsetY)
            // Follow cursor drag in real time
            .offset(catEngine.dragOffset)
            
            // Sleep zZ Floating Bubble
            if catEngine.currentAction == .sleeping {
                HStack(spacing: 1.5) {
                    Text("z")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                    Text("Z")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                }
                .foregroundStyle(Color.primary)
                .shadow(color: Color.black.opacity(0.4), radius: 1, x: 0, y: 1)
                .offset(x: catEngine.isFacingLeft ? -8 : 8, y: -18 + catEngine.zBubbleOffset)
                .opacity(catEngine.zBubbleOpacity)
                .allowsHitTesting(false)
            }
            
            // Heart particle upon tapping
            if catEngine.heartOpacity > 0.01 {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.94, green: 0.15, blue: 0.28))
                    .shadow(color: Color.black.opacity(0.3), radius: 2)
                    .offset(y: -16 + catEngine.heartOffset)
                    .opacity(catEngine.heartOpacity)
                    .scaleEffect(catEngine.heartOpacity > 0.5 ? 1.2 : 0.8)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: max(32, spriteWidth), height: max(26, spriteHeight))
        .opacity(catEngine.isBeingHeld ? 0.0 : 1.0)
        .contentShape(Rectangle())
        .offset(x: catEngine.positionX, y: 0)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let mousePoint = NSEvent.mouseLocation
                    if !catEngine.isBeingHeld {
                        catEngine.onDragStarted(screenPoint: mousePoint)
                    }
                    catEngine.onDragChanged(translation: value.translation, screenPoint: mousePoint)
                }
                .onEnded { value in
                    let dragDistance = hypot(value.translation.width, value.translation.height)
                    if dragDistance < 4.0 {
                        // Considered a simple click/tap
                        catEngine.onCatTapped()
                    } else {
                        let mousePoint = NSEvent.mouseLocation
                        catEngine.onDragEnded(
                            translation: value.translation,
                            screenPoint: mousePoint,
                            actualBarWidth: catEngine.maxX + spriteWidth + 12.0
                        )
                    }
                }
        )
        .onHover { isHovering in
            FloatingPanelController.shared.isHoveringCat = isHovering
            if isHovering {
                NSCursor.openHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .zIndex(999)
        .accessibilityLabel(L10n.catCompanion(preferences.pixelCatBreed.displayName).text)
    }
}
