import SwiftUI

/// Phases of the firmware-update screen, shared by FirmwareView and its car image.
enum FwPhase { case checking, upToDate, available, downloading, downloaded, uploading, rebooting, done, failed }

/// Top-down car + center chip + OTA waves; waves brighten/animate while uploading.
struct FirmwareCarView: View {
    let phase: FwPhase
    let palette: Palette
    @State private var pulse = false

    private var wavesActive: Bool { phase == .uploading }
    private var chipIcon: String { phase == .done ? "checkmark" : (phase == .failed ? "exclamationmark" : "cpu") }
    private var chipColor: Color { phase == .failed ? palette.warn : palette.accent }

    var body: some View {
        ZStack {
            // OTA waves (concentric)
            ForEach(0..<3, id: \.self) { i in
                Circle().stroke(palette.accent, lineWidth: 2)
                    .frame(width: CGFloat(64 + i * 28), height: CGFloat(64 + i * 28))
                    .opacity(waveOpacity(i))
                    .scaleEffect(wavesActive && pulse ? 1.16 : 1.0)
                    .animation(wavesActive ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default,
                               value: pulse)
            }
            // body + windshield
            RoundedRectangle(cornerRadius: 13).fill(palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(palette.line))
                .frame(width: 64, height: 98)
            RoundedRectangle(cornerRadius: 4).fill(palette.bg.opacity(0.7))
                .frame(width: 34, height: 12).offset(y: -31)
            // 4 neutral wheels
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 5).fill(palette.idleWheel)
                    .frame(width: 22, height: 32)
                    .offset(x: i % 2 == 0 ? -33 : 33, y: i < 2 ? -36 : 36)
            }
            // center chip (cpu / done / failed)
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
        .opacity(phase == .rebooting ? 0.5 : 1)
        .onAppear { pulse = true }
    }

    private func waveOpacity(_ i: Int) -> Double {
        (wavesActive ? [0.60, 0.36, 0.18] : [0.22, 0.12, 0.05])[i]
    }
}
