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
                        Text(status.online ? L.driveConnected(status.pingMs ?? 0) : L.driveSearching)
                            .font(.system(size: 12)).foregroundStyle(p.muted)
                    }
                    Spacer()
                    SchemeToggle(scheme: $schemeRaw, palette: p)
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15))
                            .foregroundStyle(p.muted)
                            .frame(width: 34, height: 28)
                            .background(p.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(p.line))
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
        .sheet(isPresented: $showSettings) { SettingsView(palette: p) }
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

    private var statusLine: String {
        let up = status.uptimeS.map { L.driveUptime($0) } ?? L.driveUptimeUnknown
        let cal = (status.calibrated ?? false) ? L.driveCalibYes : L.driveCalibNo
        let fw = status.fw.map { L.driveFw($0) } ?? L.driveFwUnknown
        return "\(up) · \(cal) · \(fw)"
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
