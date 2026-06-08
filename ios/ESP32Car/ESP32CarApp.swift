import SwiftUI

@main
struct ESP32CarApp: App {
    var body: some Scene {
        WindowGroup {
            Text("ESP32-Car")
                .font(.title)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
        }
    }
}
