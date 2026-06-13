import SwiftUI

/// Startup gate screen: GitHub unreachable. Amber pulsing Wi-Fi glyph + retry.
struct NoInternetView: View {
    let palette: Palette
    let onRetry: () -> Void
    private var p: Palette { palette }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            HStack(spacing: 24) {
                WifiGlyph(color: p.warn)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 9) {
                    Text(L.gateNoInternetTitle).font(.system(size: 22, weight: .semibold)).foregroundStyle(p.text)
                    Text(L.gateNoInternetSub).font(.system(size: 13)).foregroundStyle(p.muted)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 260, alignment: .leading)
                    Button(action: onRetry) {
                        Text(L.fwRetry).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.warn)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(p.warn.opacity(0.15)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.warn.opacity(0.55), lineWidth: 1))
                    }.buttonStyle(.plain).padding(.top, 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
        }
    }
}

/// Concentric Wi-Fi arcs sharing one bottom-centre origin, pulsing outward (amber).
private struct WifiGlyph: View {
    let color: Color
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let origin = CGPoint(x: size.width / 2, y: size.height / 2)
                let radii: [CGFloat] = [16, 33, 50]
                for (i, r) in radii.enumerated() {
                    let phase = (t / 1.8 - Double(i) * 0.16).truncatingRemainder(dividingBy: 1)
                    let op = 0.16 + 0.84 * (0.5 - 0.5 * cos(2 * .pi * phase))
                    var path = Path()
                    path.addArc(center: origin, radius: r,
                                startAngle: .degrees(-145), endAngle: .degrees(-35), clockwise: false)
                    ctx.stroke(path, with: .color(color.opacity(op)),
                               style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
                let dotPhase = (t / 1.8).truncatingRemainder(dividingBy: 1)
                let dotOp = 0.45 + 0.55 * (0.5 - 0.5 * cos(2 * .pi * dotPhase))
                let dot = CGRect(x: origin.x - 5.5, y: origin.y - 5.5, width: 11, height: 11)
                ctx.fill(Path(ellipseIn: dot), with: .color(color.opacity(dotOp)))
            }
        }
        .frame(width: 130, height: 120)
    }
}
