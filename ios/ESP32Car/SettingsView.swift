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
                        CalibrationView(palette: palette)
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

