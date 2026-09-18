import AppKit
import AudioToolbox

/// Subtle Haptic & Audio Feedback Manager for Glancie
public final class SoundEffectsEngine {
    public static let shared = SoundEffectsEngine()
    
    public var isSoundEnabled: Bool = true
    
    private init() {}
    
    /// Trigger a subtle snap sound when docking to screen edge or notch
    public func playSnapSound() {
        guard isSoundEnabled else { return }
        // NSSound "Pop" or "Tink" system sounds
        if let sound = NSSound(named: "Tink") {
            sound.volume = 0.25
            sound.play()
        }
    }
    
    /// Trigger celebratory bubble pop on quota reset
    public func playCelebrationSound() {
        guard isSoundEnabled else { return }
        if let sound = NSSound(named: "Hero") {
            sound.volume = 0.35
            sound.play()
        }
    }

    /// Light alignment haptic for selection changes (Force Touch trackpads only).
    /// Silent no-op on hardware without a haptic actuator.
    public func playSelectionFeedback() {
        guard isSoundEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Firmer haptic for committing an action (open/close of the detail card).
    public func playImpactFeedback() {
        guard isSoundEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
