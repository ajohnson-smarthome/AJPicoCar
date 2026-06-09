import SwiftUI

struct CalibrationView: View {
    let palette: Palette
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var assign: [Corner: (pair: Int, sign: Int)] = [:]
    @State private var pending: Corner?
    @State private var saving = false
    @State private var errMsg: String?
    @State private var pulse = false
    private let client = CalibClient()

    private var identifying: Bool { pending == nil && step < 4 }

    var body: some View {
        ZStack {
            palette.bg.ignoresSafeArea()
            HStack(spacing: 24) {
                carPanel
                rightPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
        .navigationTitle(L.calibTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(palette.accent)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { pulse = true }
        }
    }

    // MARK: left — car (with concentric pulse)
    private var carPanel: some View {
        carDiagram.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var carDiagram: some View {
        ZStack {
            // pulse halo — concentric with the body, expands outward while identifying
            if identifying {
                RoundedRectangle(cornerRadius: 13).stroke(palette.warn, lineWidth: 2)
                    .frame(width: 64, height: 98)
                    .scaleEffect(pulse ? 1.32 : 1.0)
                    .opacity(pulse ? 0 : 0.55)
                    .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pulse)
            }
            RoundedRectangle(cornerRadius: 13).fill(palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(palette.line))
                .frame(width: 64, height: 98)
            RoundedRectangle(cornerRadius: 4).fill(palette.bg.opacity(0.7))
                .frame(width: 34, height: 12).offset(y: -31)
            ForEach(Corner.allCases, id: \.self) { wheelButton($0) }
        }
        .scaleEffect(1.75)
        .frame(width: 190, height: 240)
    }

    private func wheelButton(_ c: Corner) -> some View {
        let assigned = assign[c] != nil
        let isPending = pending == c
        let fill = assigned ? palette.accent : (isPending ? palette.warn : palette.idleWheel)
        return Button { tap(c) } label: {
            Text(assigned ? "✓" : c.label)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 32)
                .background(fill)
                .foregroundStyle(palette.bg)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .shadow(color: isPending ? palette.warn.opacity(0.9) : .clear, radius: 6)
        }
        .disabled(assigned)
        .offset(x: c.dx, y: c.dy)
    }

    // MARK: right — steps / actions
    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            segments
            Text(L.calibStep(min(step + 1, 4))).font(.headline).foregroundStyle(palette.text)

            if let c = pending {
                Text(L.calibWhichDir(c.label))
                    .font(.subheadline).foregroundStyle(palette.muted)
                HStack(spacing: 10) {
                    Button { assignDir(1) } label: { Label(L.calibForward, systemImage: "arrow.up") }
                        .buttonStyle(.bordered).tint(palette.accent)
                    Button { assignDir(-1) } label: { Label(L.calibBack, systemImage: "arrow.down") }
                        .buttonStyle(.bordered).tint(palette.warn)
                }
            } else if step < 4 {
                Text(L.calibSpinPrompt(step + 1))
                    .font(.subheadline).foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button { spin() } label: { Label(L.calibSpin, systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).tint(palette.accent)
            } else {
                Text(L.calibAllSet).font(.subheadline).foregroundStyle(palette.muted)
                Button { save() } label: { Label(L.calibSave, systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent).tint(palette.accent).disabled(saving)
            }

            if let e = errMsg {
                Text(e).font(.caption).foregroundStyle(palette.warn)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var segments: some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i <= step && step < 4 || i < step ? palette.accent : palette.line)
                    .frame(width: 28, height: 4)
                    .shadow(color: i == step && step < 4 ? palette.accent.opacity(0.8) : .clear, radius: 4)
            }
        }
    }

    // MARK: logic (unchanged behavior)
    private func spin() {
        errMsg = nil
        Task { await client.spin(pair: step, dir: 1) }
    }
    private func tap(_ c: Corner) {
        guard assign[c] == nil else { return }
        pending = c
    }
    private func assignDir(_ sign: Int) {
        guard let c = pending else { return }
        assign[c] = (pair: step, sign: sign)
        pending = nil
        step += 1
    }
    private func save() {
        saving = true
        errMsg = nil
        Task {
            let ok = await client.save(body: ControlModel.calibSaveBody(assign))
            saving = false
            if ok { dismiss() } else { errMsg = L.calibSaveFailed }
        }
    }
}

private extension Corner {
    var label: String { rawValue.uppercased() }
    var dx: CGFloat { (self == .fl || self == .rl) ? -33 : 33 }
    var dy: CGFloat { (self == .fl || self == .fr) ? -36 : 36 }
}
