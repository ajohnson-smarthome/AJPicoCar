import SwiftUI

/// Animated top-down car diagram driven by the current command (t, y):
/// chevron-tread wheels + predicted-trajectory rails (driving) or a spin indicator.
struct DriveDiagram: View {
    let t: Double
    let y: Double
    let palette: Palette

    private let carW: CGFloat = 44
    private let carLen: CGFloat = 70
    private let wheelW: CGFloat = 10
    private let wheelH: CGFloat = 24
    private let railGap: CGFloat = 12

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                render(&ctx, size, time: tl.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: 150, height: 200)
    }

    private func render(_ ctx: inout GraphicsContext, _ size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.56)
        let sides = ControlModel.sides(t: t, y: y)
        switch ControlModel.diagramState(t: t, y: y) {
        case .drive: drawRails(&ctx, center: center)
        case .spin:  drawSpin(&ctx, center: center, time: time)
        case .idle:  break
        }
        drawCar(&ctx, center: center)
        let halfL = carLen / 2
        let frontY = center.y - halfL + 6 + wheelH / 2
        let rearY  = center.y + halfL - 6 - wheelH / 2
        let leftX  = center.x - carW / 2 - wheelW / 2 + 1
        let rightX = center.x + carW / 2 + wheelW / 2 - 1
        drawWheel(&ctx, cx: leftX,  cy: frontY, speed: sides.left,  time: time)
        drawWheel(&ctx, cx: leftX,  cy: rearY,  speed: sides.left,  time: time)
        drawWheel(&ctx, cx: rightX, cy: frontY, speed: sides.right, time: time)
        drawWheel(&ctx, cx: rightX, cy: rearY,  speed: sides.right, time: time)
    }

    private func wheelColor(_ s: Double) -> Color {
        if s > 0.03 { return palette.accent }
        if s < -0.03 { return palette.warn }
        return palette.idleWheel
    }

    private func drawCar(_ ctx: inout GraphicsContext, center: CGPoint) {
        let body = CGRect(x: center.x - carW / 2, y: center.y - carLen / 2, width: carW, height: carLen)
        let bp = Path(roundedRect: body, cornerRadius: 11)
        ctx.fill(bp, with: .color(palette.panel))
        ctx.stroke(bp, with: .color(palette.line), lineWidth: 1)
        let wind = CGRect(x: center.x - 14, y: body.minY + 6, width: 28, height: 11)
        ctx.fill(Path(roundedRect: wind, cornerRadius: 3), with: .color(palette.bg.opacity(0.7)))
    }

    private func drawWheel(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, speed: Double, time: Double) {
        let rect = CGRect(x: cx - wheelW / 2, y: cy - wheelH / 2, width: wheelW, height: wheelH)
        let wp = Path(roundedRect: rect, cornerRadius: 3)
        ctx.fill(wp, with: .color(wheelColor(speed)))
        let mag = min(abs(speed), 1)
        guard mag > 0.03 else { return }

        var c = ctx
        c.clip(to: wp)
        let up = speed > 0
        let spacing = 14 - 7 * CGFloat(mag)
        let tempo = 70 * mag
        let offset = (CGFloat(time) * tempo).truncatingRemainder(dividingBy: spacing)
        let ch: CGFloat = 4.5
        var k = -2
        while CGFloat(k) * spacing < wheelH + spacing {
            let base = up ? (rect.maxY - CGFloat(k) * spacing + offset)
                          : (rect.minY + CGFloat(k) * spacing - offset)
            var p = Path()
            if up {
                p.move(to: CGPoint(x: rect.minX + 1, y: base + ch))
                p.addLine(to: CGPoint(x: rect.midX, y: base - ch))
                p.addLine(to: CGPoint(x: rect.maxX - 1, y: base + ch))
            } else {
                p.move(to: CGPoint(x: rect.minX + 1, y: base - ch))
                p.addLine(to: CGPoint(x: rect.midX, y: base + ch))
                p.addLine(to: CGPoint(x: rect.maxX - 1, y: base - ch))
            }
            c.stroke(p, with: .color(palette.bg), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            k += 1
        }
    }

    private func drawRails(_ ctx: inout GraphicsContext, center: CGPoint) {
        let forward = t >= 0
        let railColor = forward ? palette.accent : palette.warn
        let length = 50 + 80 * min(abs(t), 1)
        let halfW = carW / 2 + 2
        let startY = forward ? (center.y - carLen / 2 - railGap)
                             : (center.y + carLen / 2 + railGap)
        let pts = ControlModel.trajectoryPoints(t: t, y: y, length: length, steps: 24)
        let endY = startY + CGFloat(forward ? -length : length)
        let grad = Gradient(colors: [railColor.opacity(0.95), railColor.opacity(0.05)])
        for side in [CGFloat(-1), CGFloat(1)] {
            var path = Path()
            for (i, pt) in pts.enumerated() {
                let px = center.x + side * halfW + CGFloat(pt.x)
                let py = startY + (forward ? CGFloat(pt.y) : -CGFloat(pt.y))
                if i == 0 { path.move(to: CGPoint(x: px, y: py)) } else { path.addLine(to: CGPoint(x: px, y: py)) }
            }
            ctx.stroke(path, with: .linearGradient(grad,
                startPoint: CGPoint(x: center.x, y: startY),
                endPoint: CGPoint(x: center.x, y: endY)),
                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawSpin(_ ctx: inout GraphicsContext, center: CGPoint, time: Double) {
        var c = ctx
        c.translateBy(x: center.x, y: center.y)
        let sp: Double = y >= 0 ? 1 : -1                       // rotation direction
        // gentle continuous rotation so it reads as "spinning"
        let spin = time.truncatingRemainder(dividingBy: 3.0) / 3.0 * 360.0 * sp
        c.rotate(by: .degrees(spin))

        let r = 50.0
        let sweep = 110.0 * Double.pi / 180                   // arc span
        let n = 20
        for base in [0.0, Double.pi] {                        // two arcs 180° apart = ↻
            // sample the arc as a polyline so the end + tangent are unambiguous
            let start = base - sp * sweep / 2
            var pts: [CGPoint] = []
            for i in 0...n {
                let a = start + sp * sweep * Double(i) / Double(n)
                pts.append(CGPoint(x: Foundation.cos(a) * r, y: Foundation.sin(a) * r))
            }
            var path = Path()
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.addLine(to: p) }
            c.stroke(path, with: .color(palette.accent), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            // arrowhead at the END of the arc, pointing along the last segment (travel direction)
            let last = pts[pts.count - 1], prev = pts[pts.count - 2]
            let dir = Foundation.atan2(Double(last.y - prev.y), Double(last.x - prev.x))
            c.fill(arrowHead(tip: last, angle: dir, size: 13), with: .color(palette.accent))
        }
    }

    /// Filled triangular arrowhead with its tip at `tip`, pointing toward `angle` (radians).
    private func arrowHead(tip: CGPoint, angle: Double, size: CGFloat) -> Path {
        let back = angle + Double.pi
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x + Foundation.cos(back + 0.5) * Double(size),
                              y: tip.y + Foundation.sin(back + 0.5) * Double(size)))
        p.addLine(to: CGPoint(x: tip.x + Foundation.cos(back - 0.5) * Double(size),
                              y: tip.y + Foundation.sin(back - 0.5) * Double(size)))
        p.closeSubpath()
        return p
    }
}
