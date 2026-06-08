import SwiftUI

@main
struct ESP32CarApp: App {
    @StateObject private var conn = CarConnection()
    var body: some Scene {
        WindowGroup {
            ZStack {
                DriveView(conn: conn)
                if conn.state == .offline { ConnectView() }
            }
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
        }
    }
}
