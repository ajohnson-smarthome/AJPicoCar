import SwiftUI

@main
struct ESP32CarApp: App {
    @StateObject private var conn = CarConnection()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ZStack {
                DriveView(conn: conn)
                if conn.state == .offline { ConnectView() }
            }
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .onChange(of: phase) { newPhase in
                if newPhase != .active { conn.pause() }  // stop streaming in background
            }
        }
    }
}
