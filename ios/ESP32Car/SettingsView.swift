import SwiftUI

struct SettingsView: View {
    let palette: Palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                palette.bg.ignoresSafeArea()
                List {
                    NavigationLink {
                        CalibrationStub(palette: palette)
                    } label: {
                        Label("Калибровка", systemImage: "gearshape.2")
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.panel)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .tint(palette.accent)
    }
}

private struct CalibrationStub: View {
    let palette: Palette
    var body: some View {
        ZStack {
            palette.bg.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "gearshape.2").font(.largeTitle).foregroundStyle(palette.muted)
                Text("Калибровка — в разработке").foregroundStyle(palette.text)
            }
        }
        .navigationTitle("Калибровка")
        .navigationBarTitleDisplayMode(.inline)
    }
}
