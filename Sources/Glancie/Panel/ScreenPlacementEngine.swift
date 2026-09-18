import AppKit

/// Keeps the floating panel on a real screen: which display a given point
/// belongs to, and how to pull a frame back inside one.
public final class ScreenPlacementEngine {
    public static let shared = ScreenPlacementEngine()
    
    /// Room left above the panel when a frame has to be pulled down from a
    /// screen's top edge.
    public var topMargin: CGFloat = 8.0
    
    private init() {}
    
    /// Finds the screen containing or closest to the given point
    public func screen(for point: NSPoint) -> NSScreen {
        if let directScreen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            return directScreen
        }
        
        // If the point is in between screens or slightly outside, find the closest screen
        return NSScreen.screens.min(by: { s1, s2 in
            distance(from: point, to: s1.frame) < distance(from: point, to: s2.frame)
        }) ?? NSScreen.main ?? (NSScreen.screens.first ?? NSScreen())
    }
    
    /// Ensures the frame remains comfortably visible on at least one screen
    public func clampToScreens(frame: NSRect) -> NSRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return frame }
        
        // If the frame center is inside any screen's visible frame, keep it
        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let targetScreen = screens.first(where: { $0.visibleFrame.contains(center) }) {
            var adjusted = frame
            let vf = targetScreen.visibleFrame
            if adjusted.maxY > vf.maxY {
                adjusted.origin.y = vf.maxY - adjusted.height - topMargin
            }
            if adjusted.minY < vf.minY {
                adjusted.origin.y = vf.minY + 4
            }
            return adjusted
        }
        
        // Otherwise, place it safely on the closest screen
        let targetScreen = screen(for: center)
        let vf = targetScreen.visibleFrame
        var adjusted = frame
        
        if adjusted.width > vf.width {
            adjusted.size.width = vf.width - 16
        }
        
        if adjusted.minX < vf.minX {
            adjusted.origin.x = vf.minX + 8
        } else if adjusted.maxX > vf.maxX {
            adjusted.origin.x = vf.maxX - adjusted.width - 8
        }
        
        if adjusted.maxY > vf.maxY {
            adjusted.origin.y = vf.maxY - adjusted.height - topMargin
        } else if adjusted.minY < vf.minY {
            adjusted.origin.y = vf.minY + 8
        }
        
        return adjusted
    }
    
    private func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

