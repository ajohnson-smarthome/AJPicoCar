import SwiftUI

/// Phases of the firmware-update screen, shared by FirmwareView and its car image.
enum FwPhase { case checking, upToDate, available, downloading, downloaded, uploading, rebooting, done, failed }

/// Top-down car + center chip + OTA rings. Rings pulse while waiting, ping while rebooting,
/// sit static as decoration when idle, or vanish on terminal info screens.
struct FirmwareCarView: View {
    let phase: FwPhase
    let palette: Palette
    @State private var pulse = false

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
    private var animating: Bool { mode == .wait || mode == .active }

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
        .scaleEffect(1.75)
        .frame(width: 190, height: 240)
        .opacity(phase == .rebooting ? 0.6 : 1)
        .onAppear { pulse = true }
    }

    @ViewBuilder private var waves: some View {
        switch mode {
        case .none:
            EmptyView()
        case .ping:
            ForEach(0..<2, id: \.self) { i in
                Circle().stroke(palette.accent, lineWidth: 2)
                    .frame(width: 60, height: 60)
                    .scaleEffect(pulse ? 1.7 : 0.4)
                    .opacity(pulse ? 0 : 0.7)
                    .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(Double(i) * 0.9), value: pulse)
            }
        default:
            ForEach(0..<3, id: \.self) { i in
                Circle().stroke(palette.accent, lineWidth: 2)
                    .frame(width: CGFloat(64 + i * 28), height: CGFloat(64 + i * 28))
                    .opacity(ringOpacity(i))
                    .scaleEffect(animating && pulse ? 1.10 : 1.0)
                    .animation(animating ? .easeInOut(duration: mode == .active ? 1.05 : 1.3).repeatForever(autoreverses: true) : .default, value: pulse)
            }
        }
    }

    private func ringOpacity(_ i: Int) -> Double {
        switch mode {
        case .active: return [0.62, 0.38, 0.20][i]
        case .wait: return [0.42, 0.24, 0.11][i]
        case .deco: return [0.20, 0.11, 0.045][i]
        default: return 0
        }
    }
}
