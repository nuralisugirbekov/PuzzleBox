import SpriteKit
import UIKit

/// Procedural art for the rocket maze: no image assets, everything is drawn
/// once per level so the frame loop only moves a handful of nodes.
@MainActor
enum ArrowMazeArt {
    struct Random {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 1 }
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
        mutating func int(_ upperBound: Int) -> Int { Int(next() % UInt64(max(1, upperBound))) }
        mutating func unit() -> CGFloat { CGFloat(next() % 10_000) / 10_000 }
    }

    /// Each level gets its own nebula and edge-light colour.
    private static let palettes: [(nebula: [UIColor], neon: UIColor)] = [
        ([.systemPurple, .systemIndigo], .systemCyan),
        ([.systemTeal, .systemBlue], .systemMint),
        ([.systemPink, .systemPurple], .systemPink),
        ([.systemOrange, .systemRed], .systemOrange),
        ([.systemIndigo, .systemTeal], .systemTeal),
    ]

    static let softDot: SKTexture = {
        let size = CGSize(width: 32, height: 32)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                                                 endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
        }
        return SKTexture(image: image)
    }()

    // MARK: Landscape

    static func landscape(for level: ArrowMazeLevel, seed: Int) -> SKTexture {
        let tile = ArrowMazeLevel.tileSize
        let size = level.bounds.size
        let palette = palettes[seed % palettes.count]
        var random = Random(seed: UInt64(seed + 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(2, 2_400 / max(size.width, size.height))
        format.opaque = true
        // UIKit draws y-down; the maze uses SpriteKit's y-up rows.
        func rect(_ cell: ArrowMazeCell) -> CGRect {
            CGRect(x: CGFloat(cell.column) * tile, y: CGFloat(level.rows - 1 - cell.row) * tile, width: tile, height: tile)
        }
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()

            // Deep space with soft nebula clouds.
            let base = [UIColor(red: 0.03, green: 0.03, blue: 0.09, alpha: 1).cgColor,
                        UIColor(red: 0.07, green: 0.04, blue: 0.14, alpha: 1).cgColor] as CFArray
            cg.drawLinearGradient(CGGradient(colorsSpace: space, colors: base, locations: [0, 1])!,
                                  start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            for index in 0..<5 {
                let color = palette.nebula[index % palette.nebula.count]
                let center = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height)
                let radius = (0.25 + random.unit() * 0.3) * max(size.width, size.height)
                let colors = [color.withAlphaComponent(0.28).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
                cg.drawRadialGradient(CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!,
                                      startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
            }
            for _ in 0..<Int(size.width * size.height / 900) {
                let p = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height)
                let r = 0.4 + random.unit() * 1.1
                UIColor.white.withAlphaComponent(0.25 + random.unit() * 0.6).setFill()
                cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }

            // Asteroid rock fills every wall cell.
            let walls = (0..<level.rows).flatMap { row in (0..<level.columns).map { ArrowMazeCell(column: $0, row: row) } }
                .filter { !level.floors.contains($0) }
            let rockPath = UIBezierPath()
            for cell in walls { rockPath.append(UIBezierPath(rect: rect(cell))) }
            cg.saveGState()
            rockPath.addClip()
            let rock = [UIColor(red: 0.17, green: 0.15, blue: 0.24, alpha: 1).cgColor,
                        UIColor(red: 0.11, green: 0.10, blue: 0.17, alpha: 1).cgColor] as CFArray
            cg.drawLinearGradient(CGGradient(colorsSpace: space, colors: rock, locations: [0, 1])!,
                                  start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            for cell in walls {
                let r = rect(cell)
                for _ in 0..<(1 + random.int(3)) {
                    let radius = 3 + random.unit() * 10
                    let c = CGPoint(x: r.minX + random.unit() * r.width, y: r.minY + random.unit() * r.height)
                    let crater = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
                    UIColor(red: 0.07, green: 0.06, blue: 0.12, alpha: 0.85).setFill()
                    cg.fillEllipse(in: crater)
                    UIColor(white: 1, alpha: 0.08).setStroke()
                    cg.setLineWidth(1.2)
                    cg.strokeEllipse(in: crater.offsetBy(dx: 0.8, dy: 0.8))
                }
                if random.int(9) == 0 {
                    // Occasional glowing crystal shard.
                    let c = CGPoint(x: r.midX + (random.unit() - 0.5) * 30, y: r.midY + (random.unit() - 0.5) * 30)
                    let shard = UIBezierPath()
                    shard.move(to: CGPoint(x: c.x, y: c.y - 9))
                    shard.addLine(to: CGPoint(x: c.x + 5, y: c.y))
                    shard.addLine(to: CGPoint(x: c.x, y: c.y + 9))
                    shard.addLine(to: CGPoint(x: c.x - 5, y: c.y))
                    shard.close()
                    cg.setShadow(offset: .zero, blur: 8, color: palette.neon.cgColor)
                    palette.neon.withAlphaComponent(0.85).setFill()
                    shard.fill()
                    cg.setShadow(offset: .zero, blur: 0, color: nil)
                }
                for _ in 0..<4 {
                    UIColor(white: 1, alpha: 0.06).setFill()
                    cg.fill(CGRect(x: r.minX + random.unit() * r.width, y: r.minY + random.unit() * r.height, width: 1.5, height: 1.5))
                }
            }
            cg.restoreGState()

            // Neon edge lights wherever rock meets the flight corridor.
            let edges = UIBezierPath()
            for cell in level.floors {
                let r = rect(cell)
                let neighbours: [(ArrowMazeCell, CGPoint, CGPoint)] = [
                    (ArrowMazeCell(column: cell.column, row: cell.row + 1), CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY)),
                    (ArrowMazeCell(column: cell.column, row: cell.row - 1), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)),
                    (ArrowMazeCell(column: cell.column - 1, row: cell.row), CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.minX, y: r.maxY)),
                    (ArrowMazeCell(column: cell.column + 1, row: cell.row), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY)),
                ]
                for (neighbour, a, b) in neighbours where !level.floors.contains(neighbour) {
                    edges.move(to: a)
                    edges.addLine(to: b)
                }
            }
            edges.lineCapStyle = .round
            cg.setShadow(offset: .zero, blur: 12, color: palette.neon.withAlphaComponent(0.9).cgColor)
            palette.neon.withAlphaComponent(0.75).setStroke()
            edges.lineWidth = 3
            edges.stroke()
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor.white.withAlphaComponent(0.55).setStroke()
            edges.lineWidth = 1
            edges.stroke()
        }
        return SKTexture(image: image)
    }

    // MARK: Pieces

    static func buildRocket(in rocket: SKNode, flame: SKNode, reduceMotion: Bool) {
        flame.removeAllChildren()
        flame.removeAllActions()
        flame.setScale(1)
        flame.position = CGPoint(x: -17, y: 0)
        for (length, width, color) in [(CGFloat(18), CGFloat(7), UIColor.systemOrange),
                                       (CGFloat(11), CGFloat(4), UIColor(red: 1, green: 0.95, blue: 0.6, alpha: 1))] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: width))
            path.addQuadCurve(to: CGPoint(x: -length, y: 0), control: CGPoint(x: -length * 0.5, y: width))
            path.addQuadCurve(to: CGPoint(x: 0, y: -width), control: CGPoint(x: -length * 0.5, y: -width))
            path.closeSubpath()
            let node = SKShapeNode(path: path)
            node.fillColor = color
            node.strokeColor = .clear
            node.glowWidth = 0
            node.blendMode = .add
            flame.addChild(node)
        }
        if !reduceMotion {
            flame.children.first?.run(.repeatForever(.sequence([.scaleX(to: 1.25, y: 0.9, duration: 0.07),
                                                                .scaleX(to: 0.85, y: 1.05, duration: 0.07)])))
        }
        flame.zPosition = -1
        rocket.addChild(flame)

        let finColor = UIColor(red: 0.95, green: 0.27, blue: 0.33, alpha: 1)
        for side: CGFloat in [1, -1] {
            let fin = CGMutablePath()
            fin.move(to: CGPoint(x: -4, y: 6 * side))
            fin.addLine(to: CGPoint(x: -17, y: 13 * side))
            fin.addLine(to: CGPoint(x: -17, y: 5 * side))
            fin.closeSubpath()
            let node = SKShapeNode(path: fin)
            node.fillColor = finColor
            node.strokeColor = UIColor(white: 0, alpha: 0.25)
            node.lineWidth = 1
            rocket.addChild(node)
        }

        let body = CGMutablePath()
        body.move(to: CGPoint(x: -17, y: 6))
        body.addLine(to: CGPoint(x: 6, y: 7))
        body.addQuadCurve(to: CGPoint(x: 21, y: 0), control: CGPoint(x: 17, y: 6))
        body.addQuadCurve(to: CGPoint(x: 6, y: -7), control: CGPoint(x: 17, y: -6))
        body.addLine(to: CGPoint(x: -17, y: -6))
        body.closeSubpath()
        let hull = SKShapeNode(path: body)
        hull.fillColor = UIColor(red: 0.94, green: 0.95, blue: 0.99, alpha: 1)
        hull.strokeColor = UIColor(red: 0.6, green: 0.65, blue: 0.78, alpha: 1)
        hull.lineWidth = 1.2
        rocket.addChild(hull)

        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: 12, y: 5.4))
        nose.addQuadCurve(to: CGPoint(x: 21, y: 0), control: CGPoint(x: 18, y: 4))
        nose.addQuadCurve(to: CGPoint(x: 12, y: -5.4), control: CGPoint(x: 18, y: -4))
        nose.closeSubpath()
        let cone = SKShapeNode(path: nose)
        cone.fillColor = finColor
        cone.strokeColor = .clear
        rocket.addChild(cone)

        let stripe = SKShapeNode(rect: CGRect(x: -12, y: -6.2, width: 3, height: 12.4))
        stripe.fillColor = finColor
        stripe.strokeColor = .clear
        rocket.addChild(stripe)

        let window = SKShapeNode(circleOfRadius: 3.6)
        window.position = CGPoint(x: 3, y: 0)
        window.fillColor = UIColor(red: 0.35, green: 0.8, blue: 1, alpha: 1)
        window.strokeColor = UIColor(red: 0.45, green: 0.5, blue: 0.62, alpha: 1)
        window.lineWidth = 1.6
        rocket.addChild(window)
    }

    static func star(radius: CGFloat, reduceMotion: Bool, phase: Double) -> SKNode {
        let node = SKNode()
        let glow = SKSpriteNode(texture: softDot)
        glow.size = CGSize(width: radius * 4.4, height: radius * 4.4)
        glow.color = .systemYellow
        glow.colorBlendFactor = 1
        glow.alpha = 0.55
        glow.blendMode = .add
        node.addChild(glow)
        let path = CGMutablePath()
        for point in 0..<10 {
            let angle = CGFloat(point) * .pi / 5 + .pi / 2
            let r = point.isMultiple(of: 2) ? radius * 1.15 : radius * 0.5
            let p = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            if point == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        let shape = SKShapeNode(path: path)
        shape.fillColor = UIColor(red: 1, green: 0.85, blue: 0.25, alpha: 1)
        shape.strokeColor = UIColor.white.withAlphaComponent(0.9)
        shape.lineWidth = 1.2
        shape.lineJoin = .round
        node.addChild(shape)
        if !reduceMotion {
            shape.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 4)))
            glow.run(.sequence([.wait(forDuration: phase.truncatingRemainder(dividingBy: 1)),
                                .repeatForever(.sequence([.fadeAlpha(to: 0.85, duration: 0.6),
                                                          .fadeAlpha(to: 0.4, duration: 0.6)]))]))
        }
        return node
    }

    static func decoratePortal(_ ring: SKShapeNode, reduceMotion: Bool) {
        let radius = ArrowMazeSimulation.exitRadius
        let dashes = CGMutablePath()
        for index in 0..<6 {
            let start = CGFloat(index) * .pi / 3
            dashes.addArc(center: .zero, radius: radius * 0.68, startAngle: start, endAngle: start + .pi / 5, clockwise: false)
            dashes.move(to: CGPoint(x: cos(start + .pi / 3) * radius * 0.68, y: sin(start + .pi / 3) * radius * 0.68))
        }
        let inner = SKShapeNode(path: dashes)
        inner.lineWidth = 2.5
        inner.lineCap = .round
        ring.addChild(inner)
        let core = SKShapeNode(circleOfRadius: radius * 0.3)
        core.lineWidth = 2
        ring.addChild(core)
        if !reduceMotion {
            inner.run(.repeatForever(.rotate(byAngle: -.pi * 2, duration: 3)))
        }
    }

    static func sparkBurst(at point: CGPoint, color: UIColor, count: Int = 16) -> SKNode {
        let burst = SKEmitterNode()
        burst.particleTexture = softDot
        burst.position = point
        burst.zPosition = 6
        burst.numParticlesToEmit = count
        burst.particleBirthRate = 600
        burst.particleLifetime = 0.55
        burst.particleSpeed = 110
        burst.particleSpeedRange = 60
        burst.emissionAngleRange = .pi * 2
        burst.particleScale = 0.35
        burst.particleScaleSpeed = -0.5
        burst.particleAlphaSpeed = -1.6
        burst.particleColor = color
        burst.particleColorBlendFactor = 1
        burst.particleBlendMode = .add
        burst.run(.sequence([.wait(forDuration: 1.2), .removeFromParent()]))
        return burst
    }
}
