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
    @State private var showSettings = false
    @State private var showCalib = false
    @State private var didPromptCalib = false

    @StateObject private var pad = Gamepad()
    @State private var haptics = Haptics()

    init(conn: CarConnection, status: CarStatus) {
        _conn = ObservedObject(wrappedValue: conn)
        _status = ObservedObject(wrappedValue: status)
    }

    private var scheme: Scheme { Scheme(rawValue: schemeRaw) ?? .arcade }
    private var p: Palette { Theme.current(colorScheme) }
    private var signalLevel: Int { ControlModel.signalLevel(online: status.online, pingMs: status.pingMs) }
    private var signalColor: Color { signalLevel == 0 ? .red : (signalLevel == 1 ? p.warn : p.accent) }

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
                        SignalBars(level: signalLevel, color: signalColor)
                        Text(status.online ? L.driveConnected(status.pingMs ?? 0) : L.driveSearching)
                            .font(.system(size: 12)).foregroundStyle(p.muted)
                    }
                    Spacer()
                    SchemeToggle(scheme: $schemeRaw, palette: p)
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(p.text)
                            .frame(width: 40, height: 32)
                            .background(p.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.line))
                    }
                    .padding(.leading, 8)
                }
                .padding(.horizontal, 18).padding(.top, 8)
                Spacer()
            }

            HStack(spacing: 34) {
                sideLabel(L.sideLeft, sides.left)
                DriveDiagram(t: curT, y: curY, palette: p)
                sideLabel(L.sideRight, sides.right)
            }

            VStack {
                Spacer()
                statusBar.padding(.bottom, 20)
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
        .sheet(isPresented: $showSettings) { SettingsView(palette: p, status: status) }
        .onReceive(status.$calibrated) { cal in
            if cal == false && !didPromptCalib { didPromptCalib = true; showCalib = true }
        }
        .sheet(isPresented: $showCalib) {
            NavigationStack {
                CalibrationView(palette: p)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(L.later) { showCalib = false } }
                    }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            statusItem("clock", status.uptimeS.map { L.uptime($0) } ?? "—", p.muted)
            let ok = status.calibrated ?? false
            statusItem(ok ? "checkmark.circle.fill" : "xmark.circle",
                       ok ? L.driveCalibratedYes : L.driveCalibratedNo,
                       ok ? p.accent : p.warn)
            statusItem("cpu", status.fw ?? "—", p.muted)
        }
        .font(.system(size: 10))
    }
    private func statusItem(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color.opacity(0.85))
            Text(text).foregroundStyle(color)
        }
    }

    private func sideLabel(_ name: String, _ v: Double) -> some View {
        VStack(spacing: 2) {
            Text(name).font(.system(size: 13)).foregroundStyle(p.accent)
            Text("\(Int(v * 100))%")
                .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                .foregroundStyle(p.accent)
        }
        .frame(width: 64)  // fixed width so the car doesn't shift as the % text changes
    }
}
