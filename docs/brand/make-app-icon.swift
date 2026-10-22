import AppKit
import CoreGraphics

enum Variant { case light, dark, tinted }
let size: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gray(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: v, green: v, blue: v, alpha: a) }

// Geometry (y up). The "o", the "i" and the ball keep the wordmark's proportions.
let oCenter = CGPoint(x: 392, y: 440), oRadius: CGFloat = 138, stroke: CGFloat = 100
let iX: CGFloat = 754, iTop: CGFloat = 560, iBottom: CGFloat = 302
let ballCenter = CGPoint(x: 754, y: 740), ballRadius: CGFloat = 64
let depth: CGFloat = 36

struct Palette { let bg1, bg2, o, oSide, i, iSide, ball, ballSide: CGColor; let trail: CGColor }

func render(_ v: Variant, to path: String) {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let p: Palette
    switch v {
    case .light: p = Palette(bg1: rgb(0x6A4BFF), bg2: rgb(0x3A2BC4), o: rgb(0xFFC83D), oSide: rgb(0xE08F00), i: rgb(0x2EE6A6), iSide: rgb(0x0E9E73), ball: rgb(0xFF5A4F), ballSide: rgb(0xC62E2A), trail: gray(1, 0.8))
    case .dark: p = Palette(bg1: rgb(0x2B1D8F), bg2: rgb(0x120B45), o: rgb(0xFFC83D), oSide: rgb(0xD98400), i: rgb(0x2EE6A6), iSide: rgb(0x0B8A63), ball: rgb(0xFF5A4F), ballSide: rgb(0xB82A26), trail: gray(1, 0.7))
    case .tinted: p = Palette(bg1: gray(0), bg2: gray(0), o: gray(1), oSide: gray(0.45), i: gray(0.82), iSide: gray(0.38), ball: gray(0.68), ballSide: gray(0.3), trail: gray(0.6, 0.9))
    }
    // Background: two-stop diagonal, flat and clean.
    ctx.drawLinearGradient(CGGradient(colorsSpace: cs, colors: [p.bg1, p.bg2] as CFArray, locations: [0, 1])!,
                           start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    if v != .tinted {
        // A faint tile grid, like a game board under the pieces.
        ctx.setStrokeColor(gray(1, 0.07)); ctx.setLineWidth(4)
        for k in stride(from: CGFloat(0), through: size, by: 128) {
            ctx.move(to: CGPoint(x: k, y: 0)); ctx.addLine(to: CGPoint(x: k, y: size))
            ctx.move(to: CGPoint(x: 0, y: k)); ctx.addLine(to: CGPoint(x: size, y: k))
        }
        ctx.strokePath()
    }

    func ring(_ dy: CGFloat, _ color: CGColor) {
        ctx.setStrokeColor(color); ctx.setLineWidth(stroke)
        ctx.addEllipse(in: CGRect(x: oCenter.x - oRadius, y: oCenter.y - oRadius + dy, width: oRadius * 2, height: oRadius * 2))
        ctx.strokePath()
    }
    func bar(_ dy: CGFloat, _ color: CGColor) {
        ctx.setStrokeColor(color); ctx.setLineWidth(stroke); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: iX, y: iTop + dy)); ctx.addLine(to: CGPoint(x: iX, y: iBottom + dy)); ctx.strokePath()
    }
    func ball(_ dy: CGFloat, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: ballCenter.x - ballRadius, y: ballCenter.y - ballRadius + dy, width: ballRadius * 2, height: ballRadius * 2))
    }
    // Shadow on the "table".
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -34), blur: 36, color: gray(0, v == .tinted ? 0 : 0.35))
    ring(-depth, p.oSide); bar(-depth, p.iSide); ball(-depth * 0.8, p.ballSide)
    ctx.restoreGState()
    // Solid extrusion: stack of offset copies makes the toy-block thickness.
    for d in stride(from: depth, to: 0, by: -4) { ring(-d, p.oSide); bar(-d, p.iSide); ball(-d * 0.8, p.ballSide) }
    // Faces.
    ring(0, p.o); bar(0, p.i); ball(0, p.ball)
    if v != .tinted {
        // One small highlight on the ball: the only "shine" in the whole icon.
        ctx.setFillColor(gray(1, 0.9))
        ctx.fillEllipse(in: CGRect(x: ballCenter.x - 30, y: ballCenter.y + 18, width: 24, height: 24))
        // Dashed bounce trail from the ring up to the ball.
        ctx.setStrokeColor(p.trail); ctx.setLineWidth(14); ctx.setLineCap(.round); ctx.setLineDash(phase: 0, lengths: [2, 34])
        ctx.move(to: CGPoint(x: 440, y: 640))
        ctx.addQuadCurve(to: CGPoint(x: 676, y: 770), control: CGPoint(x: 480, y: 860))
        ctx.strokePath(); ctx.setLineDash(phase: 0, lengths: [])
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
render(.light, to: "AppIcon.png"); render(.dark, to: "AppIcon-Dark.png"); render(.tinted, to: "AppIcon-Tinted.png")
print("ok")
