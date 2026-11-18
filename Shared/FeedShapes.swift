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

// MARK: - Sleep, nappies, medicine and growth (06-more-than-feeds.md, 17 Nov 2026)

extension Grid24 {
    /// A point given on the round-two mockup's 20 by 20 grid.
    func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { p(x * 1.2, y * 1.2) }
}

/// A crescent moon, for sleep.
struct MoonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid24(rect)
        let disc = Path(ellipseIn: CGRect(x: g.p(2.4, 3.6).x, y: g.p(2.4, 3.6).y, width: g.r(18), height: g.r(18)))
        let bite = Path(ellipseIn: CGRect(x: g.p(9.6, -0.6).x, y: g.p(9.6, -0.6).y, width: g.r(15), height: g.r(15)))
        return disc.subtracting(bite)
    }
}

/// One drop, for a wet nappy (wee).
struct DropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid24(rect)
        var path = Path()
        let top = g.p(12, 2.6), radius: CGFloat = 6.7, cx: CGFloat = 12, cy: CGFloat = 15.2
        path.move(to: top)
        path.addCurve(to: g.p(cx + radius, cy), control1: top, control2: g.p(cx + radius, cy - (cy - 2.6) * 0.41))
        path.addArc(center: g.p(cx, cy), radius: g.r(radius), startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addCurve(to: top, control1: g.p(cx - radius, cy - (cy - 2.6) * 0.41), control2: top)
        path.closeSubpath()
        return path
    }
}

/// A soft swirl, for a dirty nappy (poo).
struct PooShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid24(rect)
        var path = Path()
        path.move(to: g.q(3.4, 15.6))
        path.addCurve(to: g.q(6.4, 11.4), control1: g.q(2.6, 12.4), control2: g.q(5, 11.4))
        path.addCurve(to: g.q(10.4, 7.6), control1: g.q(6.2, 8.6), control2: g.q(8.4, 7.2))
        path.addCurve(to: g.q(14, 5.2), control1: g.q(10.2, 5.4), control2: g.q(12.6, 3.6))
        path.addCurve(to: g.q(14.2, 9.6), control1: g.q(15.8, 7.2), control2: g.q(14.6, 9))
        path.addCurve(to: g.q(16.6, 15.6), control1: g.q(16.4, 10), control2: g.q(17.8, 12.4))
        path.closeSubpath()
        return path
    }
}

/// A spoon, for a medicine or vitamin: a solid bowl and a handle.
struct SpoonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid24(rect)
        var handle = Path()
        handle.move(to: g.q(9.4, 9.4))
        handle.addLine(to: g.q(16.8, 16.8))
        var path = handle.strokedPath(StrokeStyle(lineWidth: g.r(2.8), lineCap: .round))
        let bowl = Path(ellipseIn: CGRect(x: -g.r(5.2), y: -g.r(3.7), width: g.r(10.4), height: g.r(7.4)))
        path.addPath(bowl, transform: CGAffineTransform(rotationAngle: .pi / 4)
            .concatenating(CGAffineTransform(translationX: g.q(7, 7).x, y: g.q(7, 7).y)))
        return path
    }
}

/// A line going up, for growth.
struct GrowthShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid24(rect)
        var line = Path()
        line.move(to: g.q(3, 16.5))
        line.addLine(to: g.q(8, 11))
        line.addLine(to: g.q(11, 13.5))
        line.addLine(to: g.q(17, 6))
        line.move(to: g.q(13, 6))
        line.addLine(to: g.q(17, 6))
        line.addLine(to: g.q(17, 10))
        return line.strokedPath(StrokeStyle(lineWidth: g.r(2.6), lineCap: .round, lineJoin: .round))
    }
}

/// A closed eye: the lid as a curve, with three lashes. On the Sleep and nappy widget it is the
/// Fell asleep button (the users' ask, 17 Nov 2026).
/// A first in the journal: a rounded four-point sparkle (design review D26), never a star.
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let x = rect.midX - 12 * s
        let y = rect.midY - 12 * s
        func p(_ px: CGFloat, _ py: CGFloat) -> CGPoint { CGPoint(x: x + px * s, y: y + py * s) }
        var path = Path()
        path.move(to: p(12, 2))
        path.addCurve(to: p(20, 10), control1: p(12.9, 6.6), control2: p(15.4, 9.1))
        path.addCurve(to: p(12, 18), control1: p(15.4, 10.9), control2: p(12.9, 13.4))
        path.addCurve(to: p(4, 10), control1: p(11.1, 13.4), control2: p(8.6, 10.9))
        path.addCurve(to: p(12, 2), control1: p(8.6, 9.1), control2: p(11.1, 6.6))
        path.closeSubpath()
        return path
    }
}

struct ClosedEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid24(rect)
        var line = Path()
        line.move(to: g.p(3, 10))
        line.addQuadCurve(to: g.p(21, 10), control: g.p(12, 19.5))
        for (from, to) in [((6.4, 13.4), (4.6, 16.4)), ((12, 14.8), (12, 18.6)), ((17.6, 13.4), (19.4, 16.4))] {
            line.move(to: g.p(from.0, from.1))
            line.addLine(to: g.p(to.0, to.1))
        }
        return line.strokedPath(StrokeStyle(lineWidth: g.r(2.4), lineCap: .round, lineJoin: .round))
    }
}

/// An open eye: an almond outline with a round pupil. On the Sleep and nappy widget it is the
/// Woke up button.
struct OpenEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = Grid24(rect)
        var outline = Path()
        outline.move(to: g.p(2.5, 12))
        outline.addQuadCurve(to: g.p(21.5, 12), control: g.p(12, 2.5))
        outline.addQuadCurve(to: g.p(2.5, 12), control: g.p(12, 21.5))
        outline.closeSubpath()
        var path = outline.strokedPath(StrokeStyle(lineWidth: g.r(2.4), lineCap: .round, lineJoin: .round))
        path.addEllipse(in: CGRect(x: g.p(8.6, 8.6).x, y: g.p(8.6, 8.6).y, width: g.r(6.8), height: g.r(6.8)))
        return path
    }
}
