import SwiftUI

struct SettingsView: View {
    let palette: Palette
    @ObservedObject var status: CarStatus
    @Environment(\.dismiss) private var dismiss
    @State private var rampMs = 300

    var body: some View {
        NavigationStack {
            ZStack {
                palette.bg.ignoresSafeArea()
                List {
                    NavigationLink {
                        CalibrationView(palette: palette)
                    } label: {
                        Label(L.settingsCalibration, systemImage: "gearshape.2")
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.panel)
                    NavigationLink {
                        FirmwareView(palette: palette, status: status)
                    } label: {
                        Label(L.settingsFirmware, systemImage: "arrow.down.circle")
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.panel)
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(rampMs > 0 ? L.rampLabel(rampMs) : L.rampOff)
                                .font(.system(size: 14)).foregroundStyle(palette.text)
                            Slider(value: Binding(
                                get: { Double(rampMs) },
                                set: { rampMs = Int($0 / 50) * 50 }
                            ), in: 0...1000) { editing in
                                if !editing { Task { await RampClient().set(rampMs) } }
                            }
                            .tint(palette.accent)
                        }
                        .listRowBackground(palette.panel)
                    } header: {
                        Text(L.rampTitle).foregroundStyle(palette.muted)
                    }
                }
                .scrollContentBackground(.hidden)
                .task { if let v = await RampClient().get() { rampMs = v } }
            }
            .navigationTitle(L.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.close) { dismiss() }
                }
            }
        }
        .tint(palette.accent)
    }
}

