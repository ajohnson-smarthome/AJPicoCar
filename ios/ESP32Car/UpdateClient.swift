import Foundation

/// Fetches the latest firmware from GitHub Releases and uploads it to the car's /ota.
@MainActor
final class UpdateClient: NSObject, ObservableObject {
    struct Release { let tag: String; let assetURL: URL }
    @Published var uploadProgress: Double = 0

    private let repo = "ajohnson-smarthome/AJPicoCar"

    /// Normalize a version like "v1.2" / "v1.2-3-gabc" → "1.2" for comparison.
    static func normalize(_ v: String?) -> String {
        guard let v else { return "" }
        var s = v
        if s.hasPrefix("v") { s.removeFirst() }
        if let dash = s.firstIndex(of: "-") { s = String(s[s.startIndex..<dash]) }
        return s
    }

    func latestRelease() async -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = j["tag_name"] as? String,
                  let assets = j["assets"] as? [[String: Any]] else { return nil }
            let bin = assets.first { ($0["name"] as? String)?.hasSuffix(".bin") == true }
            guard let s = bin?["browser_download_url"] as? String, let u = URL(string: s) else { return nil }
            return Release(tag: tag, assetURL: u)
        } catch { return nil }
    }

    func download(_ url: URL) async -> URL? {
        do {
            let (tmp, _) = try await URLSession.shared.download(from: url)
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("firmware.bin")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            return dest
        } catch { return nil }
    }

    func upload(_ binURL: URL) async -> Bool {
        guard let url = URL(string: CarHost.httpBase + "/ota") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (_, resp) = try await session.upload(for: req, fromFile: binURL)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }
}

extension UpdateClient: URLSessionTaskDelegate {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                                totalBytesExpectedToSend: Int64) {
        let p = totalBytesExpectedToSend > 0 ? Double(totalBytesSent) / Double(totalBytesExpectedToSend) : 0
        Task { @MainActor in self.uploadProgress = p }
    }
}
