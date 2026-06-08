import SwiftUI

/// Top-down car with 4 wheels. left/right are side speeds in [-1,1]
/// (FL/RL = left, FR/RR = right). Arrow = direction, brightness/glow = |speed|.
struct WheelsView: View {
    let left: Double
    let right: Double
    let palette: Palette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13).fill(palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(palette.line))
                .frame(width: 46, height: 74)
            RoundedRectangle(cornerRadius: 5).fill(palette.bg.opacity(0.6))
                .frame(width: 24, height: 12).offset(y: -6)

            wheel(left).offset(x: -30, y: -33)
            wheel(left).offset(x: -30, y: 33)
            wheel(right).offset(x: 30, y: -33)
            wheel(right).offset(x: 30, y: 33)
        }
        .frame(width: 84, height: 104)
    }

    private func wheel(_ v: Double) -> some View {
        let s = min(abs(v), 1)
        let active = s > 0.05
        return RoundedRectangle(cornerRadius: 5)
            .fill(active ? palette.accent.opacity(0.4 + 0.6 * s) : palette.idleWheel)
            .frame(width: 16, height: 26)
            .overlay(
                Image(systemName: v >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.bg)
                    .opacity(active ? 1 : 0)
            )
            .shadow(color: active ? palette.accent.opacity(s) : .clear, radius: 8 * s)
            .animation(.easeOut(duration: 0.12), value: v)
    }
}
