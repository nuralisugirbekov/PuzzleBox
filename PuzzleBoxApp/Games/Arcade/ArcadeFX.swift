import SwiftUI

/// Lightweight "juice" layer shared by the arcade-style engines: particles,
/// floating score popups, screen shake and a short screen flash.
/// Everything lives in playfield coordinates and is advanced by the engine.
struct ArcadeFXParticle {
    var p: CGPoint
    var v: CGVector
    var life: CGFloat
    let maxLife: CGFloat
    let size: CGFloat
    let color: Color
    let gravity: CGFloat
}

struct ArcadeFXPopup {
    let text: String
    var p: CGPoint
    var life: CGFloat
    let color: Color
    let size: CGFloat
}

struct ArcadeFX {
    private(set) var particles: [ArcadeFXParticle] = []
    private(set) var popups: [ArcadeFXPopup] = []
    private(set) var shake: CGFloat = 0
    private(set) var flash: CGFloat = 0
    private(set) var flashColor: Color = .white
    private var clock: CGFloat = 0

    private static let maxParticles = 180
    private static let popupLife: CGFloat = 0.9

    var isIdle: Bool { particles.isEmpty && popups.isEmpty && shake == 0 && flash == 0 }

    mutating func reset() { self = ArcadeFX() }

    mutating func burst(at p: CGPoint, color: Color, count: Int = 12, speed: CGFloat = 140,
                        gravity: CGFloat = 320, size: CGFloat = 3, life: CGFloat = 0.6,
                        angles: ClosedRange<CGFloat> = 0...(2 * .pi)) {
        let room = max(0, Self.maxParticles - particles.count)
        for _ in 0..<min(count, room) {
            let a = CGFloat.random(in: angles)
            let s = speed * CGFloat.random(in: 0.35...1)
            let l = life * CGFloat.random(in: 0.6...1)
            particles.append(ArcadeFXParticle(p: p, v: CGVector(dx: cos(a) * s, dy: sin(a) * s),
                                              life: l, maxLife: l, size: size * CGFloat.random(in: 0.6...1.3),
                                              color: color, gravity: gravity))
        }
    }

    mutating func popup(_ text: String, at p: CGPoint, color: Color = .white, size: CGFloat = 16) {
        if popups.count >= 6 { popups.removeFirst() }
        popups.append(ArcadeFXPopup(text: text, p: p, life: Self.popupLife, color: color, size: size))
    }

    mutating func kick(_ amount: CGFloat) { shake = max(shake, amount) }

    mutating func flash(_ color: Color, _ amount: CGFloat = 0.35) {
        flashColor = color; flash = max(flash, amount)
    }

    mutating func update(_ dt: CGFloat) {
        guard !isIdle else { return }
        clock += dt
        if !particles.isEmpty {
            for i in particles.indices {
                particles[i].v.dy += particles[i].gravity * dt
                particles[i].p.x += particles[i].v.dx * dt
                particles[i].p.y += particles[i].v.dy * dt
                particles[i].life -= dt
            }
            particles.removeAll { $0.life <= 0 }
        }
        if !popups.isEmpty {
            for i in popups.indices { popups[i].p.y -= 42 * dt; popups[i].life -= dt }
            popups.removeAll { $0.life <= 0 }
        }
        shake = max(0, shake - dt * (10 + shake * 7))
        flash = max(0, flash - dt * 1.6)
    }

    func shakeOffset(reduceMotion: Bool) -> CGSize {
        guard !reduceMotion, shake > 0 else { return .zero }
        return CGSize(width: sin(clock * 73) * shake, height: cos(clock * 59) * shake * 0.7)
    }

    /// Draws particles and popups. Call after the scene, before any HUD.
    func draw(in context: inout GraphicsContext) {
        for particle in particles {
            let alpha = max(0, min(1, particle.life / particle.maxLife))
            let r = particle.size
            context.fill(Path(ellipseIn: CGRect(x: particle.p.x - r, y: particle.p.y - r, width: r * 2, height: r * 2)),
                         with: .color(particle.color.opacity(Double(alpha))))
        }
        for popup in popups {
            let t = popup.life / Self.popupLife
            let alpha = Double(min(1, t * 2.5))
            let scale = 1 + max(0, t - 0.8) * 2
            var text = context
            text.opacity = alpha
            text.translateBy(x: popup.p.x, y: popup.p.y)
            text.scaleBy(x: scale, y: scale)
            text.draw(Text(popup.text)
                        .font(.system(size: popup.size, weight: .heavy, design: .rounded))
                        .foregroundStyle(popup.color),
                      at: .zero)
        }
    }

    /// Full-screen flash; suppressed when Reduce Motion is on.
    func drawFlash(in context: inout GraphicsContext, bounds: CGRect, reduceMotion: Bool) {
        guard flash > 0, !reduceMotion else { return }
        context.fill(Path(bounds), with: .color(flashColor.opacity(Double(min(0.45, flash)))))
    }
}
