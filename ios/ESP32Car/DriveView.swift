import SwiftUI

struct DriveView: View {
    @ObservedObject var conn: CarConnection
    @ObservedObject var status: CarStatus
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("scheme") private var schemeRaw = Scheme.arcade.rawValue

    @State private var arcX = 0.0
    @State private var arcY = 0.0
    @State private var leftY = 0.0
    @State private var rightY = 0.0
    @State private var curT = 0.0
    @State private var curY = 0.0

    @StateObject private var pad = Gamepad()
    @State private var haptics = Haptics()

    init(conn: CarConnection, status: CarStatus) {
        _conn = ObservedObject(wrappedValue: conn)
        _status = ObservedObject(wrappedValue: status)
    }

    private var scheme: Scheme { Scheme(rawValue: schemeRaw) ?? .arcade }
    private var p: Palette { Theme.current(colorScheme) }

    private func push() {
        let c: (t: Double, y: Double)
        let padActive = pad.connected && (abs(pad.leftX) > 0.03 || abs(pad.leftY) > 0.03 || abs(pad.rightY) > 0.03)
        if padActive {
            if scheme == .arcade { c = ControlModel.arcade(stickX: pad.leftX, stickY: -pad.leftY) }
            else { c = ControlModel.tank(leftStickY: -pad.leftY, rightStickY: -pad.rightY) }
        } else if scheme == .arcade {
            c = ControlModel.arcade(stickX: arcX, stickY: arcY)
        } else {
            c = ControlModel.tank(leftStickY: leftY, rightStickY: rightY)
        }
        curT = c.t; curY = c.y
        conn.setCommand(ControlModel.frame(t: c.t, y: c.y))
    }

    private var sides: (left: Double, right: Double) { ControlModel.sides(t: curT, y: curY) }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()

            VStack {
                HStack {
                    HStack(spacing: 7) {
                        Circle().fill(status.online ? p.accent : Color.orange).frame(width: 8, height: 8)
                        Text(status.online ? "connected · \(status.pingMs ?? 0) ms" : "searching…")
                            .font(.system(size: 12)).foregroundStyle(p.muted)
                    }
                    Spacer()
                    SchemeToggle(scheme: $schemeRaw, palette: p)
                }
                .padding(.horizontal, 18).padding(.top, 8)
                Spacer()
            }

            HStack(spacing: 34) {
                sideLabel("L", sides.left)
                WheelsView(left: sides.left, right: sides.right, palette: p)
                sideLabel("R", sides.right)
            }

            VStack {
                Spacer()
                Text(statusLine).font(.system(size: 10)).foregroundStyle(p.muted).padding(.bottom, 20)
            }

            if scheme == .arcade {
                HStack {
                    Spacer()
                    JoystickView(palette: p) { x, y in
                        if arcX == 0 && arcY == 0 && (x != 0 || y != 0) { haptics.tick() }
                        arcX = x; arcY = y; push()
                    }
                    .padding(.trailing, 24)
                }
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                HStack {
                    JoystickView(vertical: true, palette: p) { _, y in leftY = y; push() }.padding(.leading, 24)
                    Spacer()
                    JoystickView(vertical: true, palette: p) { _, y in rightY = y; push() }.padding(.trailing, 24)
                }
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .onAppear { conn.start(); status.start() }
        .onReceive(pad.$leftX) { _ in push() }
        .onReceive(pad.$leftY) { _ in push() }
        .onReceive(pad.$rightY) { _ in push() }
        .onReceive(pad.$connected) { _ in push() }
    }

    private var statusLine: String {
        let up = status.uptimeS.map { "up \($0)s" } ?? "up —"
        let cal = (status.calibrated ?? false) ? "calib ✓" : "calib ✗"
        let fw = status.fw.map { "fw \($0)" } ?? "fw —"
        return "\(up) · \(cal) · \(fw)"
    }

    private func sideLabel(_ name: String, _ v: Double) -> some View {
        VStack(spacing: 2) {
            Text(name).font(.system(size: 13)).foregroundStyle(p.accent)
            Text("\(Int(v * 100))%").font(.system(size: 15, weight: .semibold)).foregroundStyle(p.accent)
        }
    }
}
