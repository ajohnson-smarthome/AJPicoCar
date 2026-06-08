import SwiftUI
import UIKit

struct ConnectView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Машинка не найдена").font(.title3).foregroundStyle(.white)
                Text("Подключись к Wi-Fi «ESP32-Car»\n(пароль drive1234) в Настройках.")
                    .multilineTextAlignment(.center).foregroundStyle(.gray)
                Button("Открыть Настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Color(white: 0.12)).foregroundStyle(Color(red: 0.29, green: 0.87, blue: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}
