import SwiftUI

struct DriveView: View {
    @ObservedObject var conn: CarConnection
    @AppStorage("scheme") private var schemeRaw = Scheme.arcade.rawValue

    @State private var arcX = 0.0
    @State private var arcY = 0.0
    @State private var leftY = 0.0
    @State private var rightY = 0.0

    @StateObject private var pad = Gamepad()
    @State private var haptics = Haptics()

    init(conn: CarConnection) {
        _conn = ObservedObject(wrappedValue: conn)
    }

    private var scheme: Scheme { Scheme(rawValue: schemeRaw) ?? .arcade }

    private func push() {
        let c: (t: Double, y: Double)
        if pad.connected {
            // gamepad: up = +1, negate to the screen-Y convention the model expects
            if scheme == .arcade { c = ControlModel.arcade(stickX: pad.leftX, stickY: -pad.leftY) }
            else { c = ControlModel.tank(leftStickY: -pad.leftY, rightStickY: -pad.rightY) }
        } else if scheme == .arcade {
            c = ControlModel.arcade(stickX: arcX, stickY: arcY)
        } else {
            c = ControlModel.tank(leftStickY: leftY, rightStickY: rightY)
        }
        conn.setCommand(ControlModel.frame(t: c.t, y: c.y))
    }
    private var throttle: Double {
        scheme == .arcade ? ControlModel.clamp(-arcY)
                          : ControlModel.tank(leftStickY: leftY, rightStickY: rightY).t
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                HStack(spacing: 10) {
                    StatusPill(state: conn.state)
                    Picker("", selection: $schemeRaw) {
                        Text("Arcade").tag(Scheme.arcade.rawValue)
                        Text("Tank").tag(Scheme.tank.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                .padding(.top, 8)
                Spacer()
            }

            if scheme == .arcade {
                HStack {
                    ThrottleBar(value: throttle).padding(.leading, 30)
                    Spacer()
                    JoystickView { x, y in
                        if arcX == 0 && arcY == 0 && (x != 0 || y != 0) { haptics.tick() }
                        arcX = x; arcY = y; push()
                    }
                    .padding(.trailing, 24)
                }
                .padding(.bottom, 24)
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                HStack {
                    JoystickView(vertical: true) { _, y in leftY = y; push() }.padding(.leading, 24)
                    Spacer()
                    JoystickView(vertical: true) { _, y in rightY = y; push() }.padding(.trailing, 24)
                }
                .padding(.bottom, 24)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .opacity(conn.state == .offline ? 0.4 : 1)
        .onAppear { conn.start() }
        .onReceive(pad.$leftX) { _ in push() }
        .onReceive(pad.$leftY) { _ in push() }
        .onReceive(pad.$rightY) { _ in push() }
    }
}

private struct StatusPill: View {
    let state: CarConnection.State
    private var text: String {
        switch state {
        case .connecting: return "connecting…"
        case .connected: return "connected"
        case .offline: return "reconnecting…"
        }
    }
    private var color: Color {
        switch state {
        case .connecting: return .yellow
        case .connected: return Color(red: 0.29, green: 0.87, blue: 0.5)
        case .offline: return .red
        }
    }
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.system(size: 12)).foregroundStyle(.gray)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(white: 0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.13)))
    }
}

private struct ThrottleBar: View {
    let value: Double
    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.09))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.13)))
            Rectangle().fill(Color(red: 0.29, green: 0.87, blue: 0.5))
                .frame(height: CGFloat(abs(value)) * 122 / 2)
                .offset(y: value >= 0 ? -CGFloat(abs(value)) * 122 / 4 : CGFloat(abs(value)) * 122 / 4)
        }
        .frame(width: 16, height: 122)
    }
}
