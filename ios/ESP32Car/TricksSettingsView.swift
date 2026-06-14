import SwiftUI

/// Settings sub-screen: per-trick duration multiplier (log slider 0.5×–12×) + per-row reset.
/// List-based (like SettingsView), custom header, system nav bar hidden for consistency.
struct TricksSettingsView: View {
    let palette: Palette
    @Environment(\.dismiss) private var dismiss
    private var p: Palette { palette }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                List {
                    ForEach(Tricks.all) { trick in
                        TrickRow(trick: trick, palette: p).listRowBackground(p.panel)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(p.accent)
            }.buttonStyle(.plain)
            Text(L.tricksTitle).font(.system(size: 17, weight: .semibold)).foregroundStyle(p.text)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
    }
}

private struct TrickRow: View {
    let trick: Trick
    let palette: Palette
    @State private var scale: Double = 1.0
    private var p: Palette { palette }
    private var isDefault: Bool { abs(scale - 1.0) < 0.01 }
    private var seconds: Double { Double(trick.totalMs) / 1000 * Tricks.clampScale(scale) }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: trick.icon).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(p.accent).frame(width: 22)
            Text(L.trickName(trick.nameKey)).font(.system(size: 13)).foregroundStyle(p.text)
                .frame(width: 92, alignment: .leading)
            Slider(value: Binding(
                get: { Tricks.scaleToSlider(scale) },
                set: { scale = Tricks.sliderToScale($0) }
            ), in: 0...1) { editing in
                if !editing { TrickSettings.setScale(trick.id, scale) }
            }
            .tint(p.accent)
            VStack(alignment: .trailing, spacing: 1) {
                Text(L.trickSec(seconds)).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(p.accent).monospacedDigit()
                Text(L.trickMult(scale)).font(.system(size: 9)).foregroundStyle(p.muted).monospacedDigit()
            }
            .frame(width: 64, alignment: .trailing)
            Button { scale = 1.0; TrickSettings.setScale(trick.id, 1.0) } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 13))
                    .foregroundStyle(isDefault ? p.muted : p.accent)
                    .frame(width: 28, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(isDefault ? p.line : p.accent.opacity(0.4)))
            }
            .buttonStyle(.plain).disabled(isDefault)
        }
        .padding(.vertical, 4)
        .onAppear { scale = TrickSettings.scale(trick.id) }
    }
}
