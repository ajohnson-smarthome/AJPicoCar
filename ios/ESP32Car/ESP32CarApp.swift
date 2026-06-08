import SwiftUI

@main
struct ESP32CarApp: App {
    @StateObject private var conn = CarConnection()
    @StateObject private var status = CarStatus()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ZStack {
                DriveView(conn: conn, status: status)
                if !status.online { ConnectView() }
            }
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .onChange(of: phase) { newPhase in
                if newPhase != .active { conn.pause() }
            }
        }
    }
}
