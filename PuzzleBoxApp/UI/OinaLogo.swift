import SwiftUI

/// Oina Games brand marks, drawn from geometry so they stay crisp at any size.
/// The wordmark lives on a 400 × 220 grid: monoline lowercase letters with an
/// x-height of 100 and a stroke of 22, plus a tracked "GAMES" line below.
enum OinaBrand {
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.17)
    static let coral = Color(red: 1.0, green: 0.35, blue: 0.31)
    static let stroke: CGFloat = 22

    /// The four letters of "oina" as one stroked path (the i's dot is separate).
    static func letters() -> Path {
        var p = Path()
        // o
        p.addEllipse(in: CGRect(x: 11, y: 61, width: 78, height: 78))
        // i
        p.move(to: CGPoint(x: 137, y: 66)); p.addLine(to: CGPoint(x: 137, y: 139))
        // n: stem, arch, stem
        p.move(to: CGPoint(x: 185, y: 139)); p.addLine(to: CGPoint(x: 185, y: 100))
        p.addArc(center: CGPoint(x: 224, y: 100), radius: 39, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: 263, y: 139))
        // a: single-storey bowl with a full-height stem
        p.addEllipse(in: CGRect(x: 311, y: 61, width: 78, height: 78))
        p.move(to: CGPoint(x: 389, y: 61)); p.addLine(to: CGPoint(x: 389, y: 139))
        return p
    }

    static let dot = CGRect(x: 137 - 14, y: 14, width: 28, height: 28)
}

struct OinaWordmark: View {
    var ink: Color = OinaBrand.ink
    var accent: Color = OinaBrand.coral
    var showsGames = true

    private var gridHeight: CGFloat { showsGames ? 220 : 160 }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 400, size.height / gridHeight)
            context.translateBy(x: (size.width - 400 * scale) / 2, y: (size.height - gridHeight * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.stroke(OinaBrand.letters(), with: .color(ink),
                           style: StrokeStyle(lineWidth: OinaBrand.stroke, lineCap: .round, lineJoin: .round))
            context.fill(Path(ellipseIn: OinaBrand.dot), with: .color(accent))
            guard showsGames else { return }
            context.draw(Text("GAMES").font(.system(size: 30, weight: .heavy, design: .rounded)).tracking(16).foregroundStyle(ink),
                         at: CGPoint(x: 208, y: 200))
        }
        .aspectRatio(400 / gridHeight, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Oina Games")
    }
}

/// The square brand mark: the "oi" from the wordmark, for icons and avatars.
struct OinaMark: View {
    var background: Color = OinaBrand.ink
    var ink: Color = .white
    var accent: Color = OinaBrand.coral

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))
            // The o and i occupy x 0…148, y 14…150 of the wordmark grid; centre them optically.
            let side = min(size.width, size.height)
            let scale = side * 0.56 / 148
            context.translateBy(x: (size.width - 148 * scale) / 2, y: (size.height - 136 * scale) / 2 - 14 * scale + side * 0.02)
            context.scaleBy(x: scale, y: scale)
            var oi = Path()
            oi.addEllipse(in: CGRect(x: 11, y: 61, width: 78, height: 78))
            oi.move(to: CGPoint(x: 137, y: 66)); oi.addLine(to: CGPoint(x: 137, y: 139))
            context.stroke(oi, with: .color(ink), style: StrokeStyle(lineWidth: OinaBrand.stroke, lineCap: .round))
            context.fill(Path(ellipseIn: OinaBrand.dot), with: .color(accent))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Oina Games")
    }
}

#Preview {
    VStack(spacing: 40) {
        OinaWordmark().frame(width: 280)
        OinaWordmark(ink: .white).frame(width: 280).padding().background(OinaBrand.ink)
        OinaMark().frame(width: 120).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
