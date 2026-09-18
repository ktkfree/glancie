import SwiftUI

/// Micro Confetti / Sparkle Particle Emitter for Quota Reset Celebrations
public struct SparkleEmitterView: View {
    @State private var particles: [SparkleParticle] = []
    
    public init() {}
    
    public var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .offset(x: particle.x, y: particle.y)
                    .opacity(particle.opacity)
                    .scaleEffect(particle.scale)
            }
        }
        .onAppear {
            emitParticles()
        }
    }
    
    private func emitParticles() {
        var newParticles: [SparkleParticle] = []
        let colors: [Color] = [.yellow, .cyan, .pink, .orange, .white]
        
        for _ in 0..<12 {
            let p = SparkleParticle(
                x: 0,
                y: 0,
                color: colors.randomElement() ?? .yellow,
                size: CGFloat.random(in: 2.0...4.0),
                opacity: 1.0,
                scale: 0.1
            )
            newParticles.append(p)
        }
        self.particles = newParticles
        
        // Animate particles outward
        withAnimation(.easeOut(duration: 0.8)) {
            for i in particles.indices {
                let angle = Double.random(in: 0...(2 * .pi))
                let distance = CGFloat.random(in: 12...28)
                particles[i].x = cos(angle) * distance
                particles[i].y = sin(angle) * distance
                particles[i].scale = 1.0
                particles[i].opacity = 0.0
            }
        }
    }
}

struct SparkleParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var color: Color
    var size: CGFloat
    var opacity: Double
    var scale: CGFloat
}
