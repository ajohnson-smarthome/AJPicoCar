import SwiftUI

/// Edits one trick's per-action durations (slider 0.1–10 s each, per distinct movement).
struct TrickEditorView: View {
    let trick: Trick
    let palette: Palette
    @Environment(\.dismiss) private var dismiss
    @State private var durs: [Int] = []
    private var p: Palette { palette }
    private var actions: [(t: Double, y: Double, count: Int)] { Tricks.distinctActions(trick) }
    private var totalSec: Double {
        Double(zip(actions, durs).reduce(0) { $0 + $1.1 * $1.0.count }) / 1000
    }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if trick.id == Tricks.donut.id {
                    // One shared scroll: animation + stats + duration sliders scroll together.
                    ScrollView {
                        VStack(spacing: 16) {
                            TrickSimView(trick: trick, durs: durs, palette: p)
                            VStack(spacing: 0) {
                                ForEach(actions.indices, id: \.self) { i in
                                    if i > 0 { Rectangle().fill(p.metal.opacity(0.25)).frame(height: 1) }
                                    row(i).padding(.horizontal, 14)
                                }
                            }
                            .background(p.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.metal.opacity(0.4), lineWidth: 1))
                            .padding(.horizontal, 16)
                            Text(L.trickTotal(totalSec))
                                .font(.system(size: 12)).foregroundStyle(p.muted).monospacedDigit()
                        }
                        .padding(.bottom, 16)
                    }
                } else {
                    controls
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if durs.isEmpty { durs = TrickSettings.durations(for: trick) } }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            List {
                ForEach(actions.indices, id: \.self) { i in
                    row(i)
                        .listRowBackground(p.panel)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }
            }
            .scrollContentBackground(.hidden)
            .tint(p.accent)
            Text(L.trickTotal(totalSec))
                .font(.system(size: 12)).foregroundStyle(p.muted).monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(p.accent)
            }.buttonStyle(.plain)
            Text(L.trickName(trick.nameKey)).font(.system(size: 17, weight: .semibold)).foregroundStyle(p.text)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
    }

    @ViewBuilder private func row(_ i: Int) -> some View {
        let a = actions[i]
        let base = Tricks.baseDurations(trick)
        let isDefault = durs.indices.contains(i) && durs[i] == base[i]
        let secs = durs.indices.contains(i) ? Double(durs[i]) / 1000 : 0
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 1) {
                Text(actionLabel(Tricks.actionDescriptor(a.t, a.y))).font(.system(size: 13)).foregroundStyle(p.text)
                if a.count > 1 { Text(L.trickCycles(a.count)).font(.system(size: 9)).foregroundStyle(p.muted) }
            }
            .frame(width: 150, alignment: .leading)
            Slider(value: Binding(
                get: { secs },
                set: { if durs.indices.contains(i) { durs[i] = Int($0 * 1000) } }
            ), in: 0.1...10) { editing in
                if !editing, durs.indices.contains(i) { TrickSettings.setDuration(trick, action: i, ms: durs[i]) }
            }
            .tint(p.accent)
            Text(L.trickSec(secs)).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(p.accent).monospacedDigit().frame(width: 54, alignment: .trailing)
            Button {
                durs[i] = base[i]; TrickSettings.reset(trick, action: i)
            } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 13))
                    .foregroundStyle(isDefault ? p.muted : p.accent)
                    .frame(width: 28, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isDefault ? p.line : p.accent.opacity(0.4)))
            }
            .buttonStyle(.plain).disabled(isDefault)
        }
        .padding(.vertical, 4)
    }

    private func actionLabel(_ d: (fwd: Int, turn: Int)) -> String {
        let dir = d.fwd > 0 ? L.actFwd : (d.fwd < 0 ? L.actBack : nil)
        let turn = d.turn > 0 ? L.actRight : (d.turn < 0 ? L.actLeft : nil)
        switch (dir, turn) {
        case let (dr?, tn?): return "\(dr)-\(tn)"
        case let (dr?, nil): return dr
        case let (nil, tn?): return "\(L.actTurn) \(tn)"
        default: return L.actFwd
        }
    }
}
