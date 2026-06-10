import SwiftUI
import UIKit

struct ConnectView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var p: Palette { Theme.current(colorScheme) }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            HStack(spacing: 24) {
                ConnectCarView(palette: p)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                rightPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L.connectTitle).font(.system(size: 22, weight: .semibold)).foregroundStyle(p.text)
            Text(L.connectBody).font(.system(size: 13)).foregroundStyle(p.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 260, alignment: .leading)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Text(L.openSettings)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(p.accent)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(p.accent.opacity(0.15)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.accent.opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 3)
        }
    }
}

/// Dimmed car with a radar sweep behind it — "searching for the car".
struct ConnectCarView: View {
    let palette: Palette
    private var metal: Color { palette.metal }
    private let carW: CGFloat = 36
    private let carLen: CGFloat = 74
    private let wheelW: CGFloat = 12
    private let wheelH: CGFloat = 20

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                render(&ctx, size, time: tl.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: 160, height: 210)
        .scaleEffect(1.45)
    }

    private func render(_ ctx: inout GraphicsContext, _ size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // radar grid: three faint rings
        for r in [46.0, 60.0, 74.0] {
            let rect = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
            ctx.stroke(Path(ellipseIn: rect), with: .color(palette.accent.opacity(0.16)), lineWidth: 1.5)
        }
        // rotating beam: 70° sector with a fading conic tail, full turn ≈ 2.6 s,
        // sweeping counter-clockwise (user preference)
        var beam = ctx
        beam.translateBy(x: center.x, y: center.y)
        beam.rotate(by: .degrees(-(time * 360 / 2.6).truncatingRemainder(dividingBy: 360)))
        var sector = Path()
        sector.move(to: .zero)
        sector.addArc(center: .zero, radius: 74,
                      startAngle: .degrees(-70), endAngle: .degrees(0), clockwise: false)
        sector.closeSubpath()
        // CCW sweep → leading (bright) edge at -70°, tail fades toward 0°
        beam.fill(sector, with: .conicGradient(
            Gradient(colors: [palette.accent.opacity(0.35), palette.accent.opacity(0.0)]),
            center: .zero, angle: .degrees(-70)))
        // dimmed car on top — "not here yet"
        var car = ctx
        car.opacity = 0.55
        drawCar(&car, center: center)
    }

    private func drawCar(_ ctx: inout GraphicsContext, center: CGPoint) {
        let body = CGRect(x: center.x - carW / 2, y: center.y - carLen / 2, width: carW, height: carLen)
        let bp = Path(roundedRect: body, cornerRadius: 11)
        ctx.fill(bp, with: .color(palette.bg))
        ctx.fill(bp, with: .color(palette.panel))
        ctx.stroke(bp, with: .color(metal), lineWidth: 1)
        let wind = CGRect(x: center.x - 11, y: body.minY + 7, width: 22, height: 9)
        ctx.fill(Path(roundedRect: wind, cornerRadius: 3), with: .color(palette.bg.opacity(0.85)))
        let wx = carW / 2 + 1
        let wy = carLen / 2 - 16
        for dx in [-wx, wx] {
            for dy in [-wy, wy] {
                let r = CGRect(x: center.x + dx - wheelW / 2, y: center.y + dy - wheelH / 2,
                               width: wheelW, height: wheelH)
                ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(metal))
            }
        }
    }
}
