import SwiftUI

/// Link-loss auto-return: toggle + history-window slider (1–10 s). Split layout like RampView.
struct RecoverView: View {
    let palette: Palette
    @State private var enabled = true
    @State private var windowSec = 5         // live slider value
    @Environment(\.dismiss) private var dismiss
    private var p: Palette { palette }

    var body: some View {
        SplitScreen(palette: p, title: L.recoverTitle, onBack: { dismiss() }) {
            RecoverCarView(active: enabled, palette: p)
        } right: {
            rightPanel
        }
        .task {
            if let c = await RecoverClient().get() {
                enabled = c.enabled
                windowSec = max(1, min(10, c.windowMs / 1000))
            }
        }
    }

    private func save() {
        Task { await RecoverClient().set(enabled: enabled, windowMs: windowSec * 1000) }
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.recoverHeadline).font(.system(size: 20, weight: .semibold)).foregroundStyle(p.text)
            Toggle(L.recoverEnable, isOn: $enabled)
                .tint(p.accent)
                .frame(width: 230)
                .onChange(of: enabled) { _ in save() }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(L.recoverWindow).font(.system(size: 12)).foregroundStyle(p.muted)
                    Spacer()
                    Text(L.recoverWindowValue(windowSec)).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(enabled ? p.accent : p.muted).monospacedDigit()
                }
                Slider(value: Binding(
                    get: { Double(windowSec) },
                    set: { windowSec = Int($0.rounded()) }
                ), in: 1...10, step: 1) { editing in
                    if !editing { save() }
                }
                .tint(p.accent)
                .disabled(!enabled)
            }
            .frame(width: 230)
            .opacity(enabled ? 1 : 0.4)
            Text(enabled ? L.recoverSubOn : L.recoverSubOff)
                .font(.system(size: 12)).foregroundStyle(p.muted)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 250, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Centred reference car (same geometry as RampCarView/TrimCarView) with a dashed
/// "retrace" trail behind it. The car is NOT moved — only the trail signals the feature.
struct RecoverCarView: View {
    let active: Bool
    let palette: Palette

    private var metal: Color { palette.metal }
    private let carW: CGFloat = 34
    private let carLen: CGFloat = 72
    private let wheelW: CGFloat = 11
    private let wheelH: CGFloat = 15

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            drawTrail(&ctx, center: center)
            drawCar(&ctx, center: center)
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
        .frame(width: 120, height: 210)
        .scaleEffect(1.6)
    }

    private func drawCar(_ ctx: inout GraphicsContext, center: CGPoint) {
        let body = CGRect(x: center.x - carW / 2, y: center.y - carLen / 2, width: carW, height: carLen)
        let bp = Path(roundedRect: body, cornerRadius: 11)
        ctx.fill(bp, with: .color(palette.bg))
        ctx.fill(bp, with: .color(palette.panel))
        ctx.stroke(bp, with: .color(metal), lineWidth: 1)
        let wind = CGRect(x: center.x - 11, y: body.minY + 7, width: 22, height: 9)
        ctx.fill(Path(roundedRect: wind, cornerRadius: 3), with: .color(palette.bg.opacity(0.85)))
    }

    // Dashed trail behind the car (downward from the rear), with a small reverse chevron.
    private func drawTrail(_ ctx: inout GraphicsContext, center: CGPoint) {
        let startY = center.y + carLen / 2 + 6
        let endY = startY + 58
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: startY))
        path.addLine(to: CGPoint(x: center.x, y: endY))
        ctx.stroke(path, with: .color(palette.accent.opacity(active ? 0.55 : 0.12)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 7]))
        var chev = Path()
        chev.move(to: CGPoint(x: center.x - 5, y: endY - 5))
        chev.addLine(to: CGPoint(x: center.x, y: endY))
        chev.addLine(to: CGPoint(x: center.x + 5, y: endY - 5))
        ctx.stroke(chev, with: .color(palette.accent.opacity(active ? 0.7 : 0.12)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}
