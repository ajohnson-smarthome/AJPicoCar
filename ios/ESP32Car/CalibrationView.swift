import SwiftUI

struct CalibrationView: View {
    let palette: Palette
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var assign: [Corner: (pair: Int, sign: Int)] = [:]
    @State private var pending: Corner?
    @State private var saving = false
    @State private var msg = "Нажми Spin и смотри, какое колесо крутится."
    private let client = CalibClient()

    var body: some View {
        ZStack {
            palette.bg.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Шаг \(min(step + 1, 4))/4").font(.headline).foregroundStyle(palette.text)
                diagram
                HStack(spacing: 10) {
                    Button { spin() } label: { Label("Spin", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent).tint(palette.accent).disabled(step >= 4)
                    if pending != nil {
                        Button { assignDir(1) } label: { Label("вперёд", systemImage: "arrow.up") }.tint(palette.accent)
                        Button { assignDir(-1) } label: { Label("назад", systemImage: "arrow.down") }.tint(palette.warn)
                    }
                    Button { save() } label: { Label("Save", systemImage: "checkmark") }
                        .disabled(step < 4 || saving)
                }
                Text(msg).font(.footnote).foregroundStyle(palette.muted).multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("Калибровка")
        .navigationBarTitleDisplayMode(.inline)
        .tint(palette.accent)
    }

    private var diagram: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.line))
                .frame(width: 92, height: 132)
            ForEach(Corner.allCases, id: \.self) { wheelButton($0) }
        }
        .frame(width: 170, height: 170)
    }

    private func wheelButton(_ c: Corner) -> some View {
        let assigned = assign[c] != nil
        let isPending = pending == c
        let fill = assigned ? palette.accent : (isPending ? palette.warn : palette.idleWheel)
        return Button { tap(c) } label: {
            Text(assigned ? "✓" : c.label)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 32, height: 42)
                .background(fill)
                .foregroundStyle(palette.bg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .disabled(assigned)
        .offset(x: c.dx, y: c.dy)
    }

    private func spin() {
        Task { await client.spin(pair: step, dir: 1) }
        msg = "Кручу мотор \(step + 1)… тапни колесо, что крутится."
    }
    private func tap(_ c: Corner) {
        guard assign[c] == nil else { return }
        pending = c
        msg = "Куда крутилось колесо \(c.label)?"
    }
    private func assignDir(_ sign: Int) {
        guard let c = pending else { return }
        assign[c] = (pair: step, sign: sign)
        pending = nil
        step += 1
        msg = step < 4 ? "Жми Spin для следующего мотора." : "Все 4 размечены — жми Save."
    }
    private func save() {
        saving = true
        Task {
            let ok = await client.save(body: ControlModel.calibSaveBody(assign))
            saving = false
            if ok { dismiss() } else { msg = "Сохранение не прошло — повтори." }
        }
    }
}

private extension Corner {
    var label: String { rawValue.uppercased() }
    var dx: CGFloat { (self == .fl || self == .rl) ? -54 : 54 }
    var dy: CGFloat { (self == .fl || self == .fr) ? -46 : 46 }
}
