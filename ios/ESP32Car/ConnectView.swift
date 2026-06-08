import SwiftUI
import UIKit

struct ConnectView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var p: Palette { Theme.current(colorScheme) }
    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Машинка не найдена").font(.title3).foregroundStyle(p.text)
                Text("Подключись к Wi-Fi «ESP32-Car»\n(пароль drive1234) в Настройках,\nзатем вернись в приложение.")
                    .multilineTextAlignment(.center).foregroundStyle(p.muted)
                Button("Открыть Настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(p.panel).foregroundStyle(p.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.line))
            }
        }
    }
}
