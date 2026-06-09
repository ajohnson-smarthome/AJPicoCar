import SwiftUI

struct SettingsView: View {
    let palette: Palette
    @ObservedObject var status: CarStatus
    @Environment(\.dismiss) private var dismiss

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
                }
                .scrollContentBackground(.hidden)
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

