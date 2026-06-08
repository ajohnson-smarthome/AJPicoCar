import Foundation

@MainActor
final class CarConnection: ObservableObject {
    enum State { case connecting, connected, offline }
    @Published private(set) var state: State = .connecting

    private let url = URL(string: "ws://192.168.4.1/ws")!
    private var task: URLSessionWebSocketTask?
    private var timer: Timer?
    private var command = "0.00,0.00"
    private var started = false

    /// Latest driving intent; streamed at 10 Hz while connected.
    func setCommand(_ s: String) { command = s }

    func start() {
        guard !started else { return }
        started = true
        connect()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard state == .connected, let task else { return }
        task.send(.string(command)) { [weak self] err in
            if err != nil { Task { @MainActor in self?.drop() } }
        }
    }

    private func connect() {
        state = .connecting
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        t.sendPing { [weak self] err in
            Task { @MainActor in
                guard let self, self.task === t else { return }
                self.state = (err == nil) ? .connected : .offline
                if err != nil { self.scheduleReconnect() }
            }
        }
        receive(on: t)
    }

    private func receive(on t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === t else { return }
                switch result {
                case .success: self.receive(on: t)
                case .failure: self.drop()
                }
            }
        }
    }

    private func drop() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .offline
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            Task { @MainActor in
                guard let self, self.state == .offline else { return }
                self.connect()
            }
        }
    }
}
