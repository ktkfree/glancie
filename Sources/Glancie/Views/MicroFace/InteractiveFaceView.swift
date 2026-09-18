import SwiftUI

/// Vector-based Micro Character Face with state-driven expressions and natural blinking
public struct InteractiveFaceView: View {
    public let state: CharacterState
    public var pupilOffset: CGSize = .zero
    
    @State private var isBlinking: Bool = false
    @State private var breathingOffset: CGFloat = 0.0
    
    public init(state: CharacterState, pupilOffset: CGSize = .zero) {
        self.state = state
        self.pupilOffset = pupilOffset
    }
    
    public var body: some View {
        ZStack {
            switch state {
            case .energetic:
                energeticFace
            case .focused:
                focusedFace
            case .tired:
                tiredFace
            case .sleeping:
                sleepingFace
            case .celebrating:
                celebratingFace
            }
        }
        .frame(width: 20, height: 14)
        .offset(y: breathingOffset)
        .onAppear {
            startBlinkLoop()
            startBreathingLoop()
        }
    }
    
    // MARK: - Expressions
    
    /// 80~100%: Sparkling smile with dynamic pupils
    private var energeticFace: some View {
        HStack(spacing: 3.5) {
            // Left Eye
            eyeContainer {
                Circle()
                    .fill(Color.primary)
                    .frame(width: 3.2, height: 3.2)
                    .offset(x: pupilOffset.width, y: pupilOffset.height)
            }
            
            // Tiny smiling mouth
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1))
                path.addQuadCurve(to: CGPoint(x: 3.5, y: 1), control: CGPoint(x: 1.75, y: 3.0))
            }
            .stroke(Color.primary, lineWidth: 0.9)
            .frame(width: 3.5, height: 3)
            
            // Right Eye
            eyeContainer {
                Circle()
                    .fill(Color.primary)
                    .frame(width: 3.2, height: 3.2)
                    .offset(x: pupilOffset.width, y: pupilOffset.height)
            }
        }
    }
    
    /// 30~79%: Smart & Calm Concentration
    private var focusedFace: some View {
        HStack(spacing: 3) {
            eyeContainer {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary)
                    .frame(width: 2.8, height: 2.8)
                    .offset(x: pupilOffset.width * 0.7, y: pupilOffset.height * 0.7)
            }
            
            Rectangle()
                .fill(Color.primary.opacity(0.8))
                .frame(width: 2.8, height: 0.8)
            
            eyeContainer {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary)
                    .frame(width: 2.8, height: 2.8)
                    .offset(x: pupilOffset.width * 0.7, y: pupilOffset.height * 0.7)
            }
        }
    }
    
    /// 10~29%: Tired expression
    private var tiredFace: some View {
        HStack(spacing: 3) {
            // Droopy eye
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1.5))
                path.addLine(to: CGPoint(x: 3, y: 2.5))
            }
            .stroke(Color.primary.opacity(0.8), lineWidth: 1.0)
            .frame(width: 3, height: 3)
            
            Circle()
                .stroke(Color.primary.opacity(0.7), lineWidth: 0.8)
                .frame(width: 2, height: 2)
            
            Path { path in
                path.move(to: CGPoint(x: 0, y: 2.5))
                path.addLine(to: CGPoint(x: 3, y: 1.5))
            }
            .stroke(Color.primary.opacity(0.8), lineWidth: 1.0)
            .frame(width: 3, height: 3)
        }
    }
    
    /// 0~9%: Sleeping zZ
    private var sleepingFace: some View {
        HStack(spacing: 2.5) {
            // Closed eyes (- -)
            Rectangle().fill(Color.secondary).frame(width: 3, height: 0.9)
            Text("z")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(Color.secondary)
                .offset(y: -2.5)
            Rectangle().fill(Color.secondary).frame(width: 3, height: 0.9)
        }
    }
    
    /// Celebratory starry eyes
    private var celebratingFace: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: 4.5))
                .foregroundColor(.primary)
            
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addQuadCurve(to: CGPoint(x: 4, y: 0.5), control: CGPoint(x: 2, y: 3.5))
            }
            .stroke(Color.primary, lineWidth: 1.0)
            .frame(width: 4, height: 3)
            
            Image(systemName: "star.fill")
                .font(.system(size: 4.5))
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Helpers
    
    @ViewBuilder
    private func eyeContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .scaleEffect(y: isBlinking ? 0.1 : 1.0)
            .animation(JellySprings.blink, value: isBlinking)
    }
    
    private func startBlinkLoop() {
        Task {
            while !Task.isCancelled {
                let delay = Double.random(in: 4.0...7.0)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await MainActor.run {
                    isBlinking = true
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
                await MainActor.run {
                    isBlinking = false
                }
            }
        }
    }
    
    private func startBreathingLoop() {
        withAnimation(JellySprings.pulse) {
            breathingOffset = -0.5
        }
    }
}
