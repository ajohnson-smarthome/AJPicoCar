import SwiftUI

/// Phases of the firmware-update screen, shared by FirmwareView and its car image.
enum FwPhase { case checking, upToDate, available, downloading, downloaded, uploading, rebooting, done, failed }

/// Top-down car + center chip + OTA rings. Rings pulse while waiting, ping while rebooting,
/// sit static as decoration when idle, or vanish on terminal info screens.
/// Animations run via TimelineView so they keep going across phase transitions.
struct FirmwareCarView: View {
    let phase: FwPhase
    let palette: Palette

    private enum WaveMode { case none, deco, wait, active, ping }
    private var mode: WaveMode {
        switch phase {
        case .checking, .downloading, .downloaded: return .wait
        case .uploading: return .active
        case .rebooting: return .ping
        case .upToDate: return .deco
        case .available, .done, .failed: return .none
        }
    }
    private var chipIcon: String {
        switch phase {
        case .upToDate, .done: return "checkmark"
        case .failed: return "exclamationmark"
        default: return "cpu"
        }
    }
    private var chipColor: Color { phase == .failed ? palette.warn : palette.accent }

    var body: some View {
        ZStack {
            waves
            RoundedRectangle(cornerRadius: 13).fill(palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(palette.line))
                .frame(width: 64, height: 98)
            RoundedRectangle(cornerRadius: 4).fill(palette.bg.opacity(0.7))
                .frame(width: 34, height: 12).offset(y: -31)
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 5).fill(palette.idleWheel)
                    .frame(width: 22, height: 32)
                    .offset(x: i % 2 == 0 ? -33 : 33, y: i < 2 ? -36 : 36)
            }
            Image(systemName: chipIcon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.bg)
                .frame(width: 26, height: 26)
                .background(chipColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: chipColor.opacity(0.7), radius: phase == .done ? 11 : 5)
        }
        .scaleEffect(1.45)
        .frame(width: 175, height: 220)
        .opacity(phase == .rebooting ? 0.6 : 1)
    }

    @ViewBuilder private var waves: some View {
        switch mode {
        case .none:
            EmptyView()
        case .deco:
            rings(scale: 1.0, opacity: [0.20, 0.11, 0.045])
        case .wait, .active:
            let op: [Double] = mode == .active ? [0.62, 0.38, 0.20] : [0.42, 0.24, 0.11]
            let period = mode == .active ? 1.05 : 1.4
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let s = 1.0 + 0.10 * (0.5 + 0.5 * sin(t * 2 * .pi / period))
                rings(scale: s, opacity: op)
            }
        case .ping:
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<2, id: \.self) { i in
                        let ph = ((t + Double(i) * 0.9) / 1.8).truncatingRemainder(dividingBy: 1)
                        Circle().stroke(palette.accent, lineWidth: 2)
                            .frame(width: 60, height: 60)
                            .scaleEffect(0.4 + 1.3 * ph)
                            .opacity(0.7 * (1 - ph))
                    }
                }
            }
        }
    }

    private func rings(scale: Double, opacity: [Double]) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle().stroke(palette.accent, lineWidth: 2)
                    .frame(width: CGFloat(64 + i * 28), height: CGFloat(64 + i * 28))
                    .opacity(opacity[i])
                    .scaleEffect(scale)
            }
        }
    }
}
