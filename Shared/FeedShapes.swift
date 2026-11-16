import SwiftUI

// The feed shapes drawn as SwiftUI shapes (DESIGN.md, "Shapes"), shared by the app, the widgets
// and the watch app.

/// Maps the mockup's 24 by 24 drawings into any square, centred.
struct Grid24 {
    let scale: CGFloat
    let origin: CGPoint

    init(_ rect: CGRect) {
        let side = min(rect.width, rect.height)
        scale = side / 24
        origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
    }

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    func r(_ value: CGFloat) -> CGFloat { value * scale }
}

/// A tall baby bottle: a teat, a neck, a body with rounded feet and two level marks. Drawn as a
/// line, like the mockup, then turned into a filled outline so it can be coloured like any shape.
struct BottleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid24(rect)
        var line = Path()
        // The teat.
        line.move(to: g.p(10, 2.5))
        line.addLine(to: g.p(14, 2.5))
        // The neck.
        line.move(to: g.p(9.6, 5))
        line.addLine(to: g.p(14.4, 5))
        line.addLine(to: g.p(15.5, 8))
        line.addLine(to: g.p(8.5, 8))
        line.closeSubpath()
        // The body, with rounded bottom corners.
        let body = CGRect(origin: g.p(8, 8), size: CGSize(width: g.r(8), height: g.r(13.5)))
        line.addPath(UnevenRoundedRectangle(bottomLeadingRadius: g.r(2), bottomTrailingRadius: g.r(2)).path(in: body))
        // Level marks.
        line.move(to: g.p(8, 12.5))
        line.addLine(to: g.p(12, 12.5))
        line.move(to: g.p(8, 16))
        line.addLine(to: g.p(12, 16))
        return line.strokedPath(StrokeStyle(lineWidth: g.r(2), lineCap: .round, lineJoin: .round))
    }
}

/// Two drops, one larger, for pumping.
struct DropsShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid24(rect)
        var path = Path()
        drop(&path, g, top: (8, 3.5), round: (8, 11.3), radius: 4.2)
        drop(&path, g, top: (16.6, 9), round: (16.6, 15.8), radius: 3.7)
        return path
    }

    /// A drop: a point at the top, curving out to a round bottom.
    private func drop(_ path: inout Path, _ g: Grid24, top: (CGFloat, CGFloat), round: (CGFloat, CGFloat), radius: CGFloat) {
        let (tx, ty) = top
        let (cx, cy) = round
        path.move(to: g.p(tx, ty))
        path.addCurve(to: g.p(cx + radius, cy), control1: g.p(tx, ty), control2: g.p(cx + radius, cy - (cy - ty) * 0.41))
        // The round bottom, from the right side down and round to the left.
        path.addArc(center: g.p(cx, cy), radius: g.r(radius), startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addCurve(to: g.p(tx, ty), control1: g.p(cx - radius, cy - (cy - ty) * 0.41), control2: g.p(tx, ty))
        path.closeSubpath()
    }
}
