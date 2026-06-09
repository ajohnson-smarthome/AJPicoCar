import SwiftUI

struct SettingsView: View {
    let palette: Palette
    @ObservedObject var status: CarStatus
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                palette.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                List {
                    NavigationLink {
                        CalibrationView(palette: palette)
                    } label: {
                        Label(L.settingsCalibration, systemImage: "gearshape.2")
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.panel)
                    NavigationLink {
                        RampView(palette: palette)
                    } label: {
                        Label(L.rampTitle, systemImage: "gauge.with.needle")
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.panel)
                    NavigationLink {
                        TrimView(palette: palette)
                    } label: {
                        Label(L.trimTitle, systemImage: "arrow.up.to.line")
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
                }
                .scrollContentBackground(.hidden)
                // Reference info lives here, off the drive screen: uptime + firmware version.
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(status.uptimeS.map { L.uptime($0) } ?? "—")
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                        Text(status.fw ?? "—")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(palette.muted)
                .padding(.bottom, 10)
                }
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

