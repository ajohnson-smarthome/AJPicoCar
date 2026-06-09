import Foundation

@MainActor
final class CarStatus: ObservableObject {
    @Published var online = false
    @Published var pingMs: Int?
    @Published var uptimeS: Int?
    @Published var calibrated: Bool?
    @Published var fw: String?
    @Published var rssi: Int?
    @Published var wdtTrips: Int?
    @Published var wsFps: Int?

    private let url = URL(string: CarHost.statusURL)!
    private var timer: Timer?
    private var failCount = 0

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
            var rs: Int?; var trips: Int?; var fps: Int?
            if let data,
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (j["device"] as? String) == "esp32-car" {
                ok = true
                up = j["uptime_s"] as? Int
                cal = j["calibrated"] as? Bool
                fwv = j["fw"] as? String
                if let r = j["rssi"] as? Int, r != 0 { rs = r }
                trips = j["wdt_trips"] as? Int
                fps = j["ws_fps"] as? Int
            }
            Task { @MainActor in
                guard let self else { return }
                if ok {
                    self.failCount = 0
                    self.online = true
                    self.pingMs = ms
                    self.uptimeS = up
                    self.calibrated = cal
                    self.fw = fwv
                    self.rssi = rs
                    self.wdtTrips = trips
                    self.wsFps = fps
                } else {
                    // Debounce: only drop offline after two consecutive misses so a single
                    // transient /status timeout can't hide the pad mid-drive.
                    self.failCount += 1
                    if self.failCount >= 2 {
                        self.online = false
                        self.pingMs = nil
                    }
                }
            }
        }.resume()
    }
}
