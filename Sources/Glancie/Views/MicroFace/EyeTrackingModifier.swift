import SwiftUI
import AppKit

/// Tracks local cursor proximity to calculate sub-pixel pupil directional offsets
public struct EyeTrackingModifier: ViewModifier {
    @Binding public var pupilOffset: CGSize
    public var maxOffset: CGFloat = 2.0
    
    @State private var trackingArea: NSTrackingArea?
    
    public func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    // Calculate normalized vector from center
                    let dx = (location.x - 14) / 14.0
                    let dy = (location.y - 14) / 14.0
                    let clampedX = max(-maxOffset, min(maxOffset, dx * maxOffset))
                    let clampedY = max(-maxOffset, min(maxOffset, dy * maxOffset))
                    withAnimation(JellySprings.eyeTrack) {
                        pupilOffset = CGSize(width: clampedX, height: clampedY)
                    }
                case .ended:
                    withAnimation(JellySprings.eyeTrack) {
                        pupilOffset = .zero
                    }
                }
            }
    }
}

public extension View {
    func trackCursorForPupils(pupilOffset: Binding<CGSize>, maxOffset: CGFloat = 2.0) -> some View {
        modifier(EyeTrackingModifier(pupilOffset: pupilOffset, maxOffset: maxOffset))
    }
}
