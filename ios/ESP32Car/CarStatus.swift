import Foundation

@MainActor
final class CarStatus: ObservableObject {
    @Published var online = false
    @Published var pingMs: Int?
    @Published var uptimeS: Int?
    @Published var calibrated: Bool?
    @Published var fw: String?

    private let url = URL(string: "http://192.168.4.1/status")!
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        let started = Date()
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            var ok = false; var up: Int?; var cal: Bool?; var fwv: String?
            if let data,
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (j["device"] as? String) == "esp32-car" {
                ok = true
                up = j["uptime_s"] as? Int
                cal = j["calibrated"] as? Bool
                fwv = j["fw"] as? String
            }
            Task { @MainActor in
                guard let self else { return }
                self.online = ok
                self.pingMs = ok ? ms : nil
                self.uptimeS = up
                self.calibrated = cal
                self.fw = fwv
            }
        }.resume()
    }
}
