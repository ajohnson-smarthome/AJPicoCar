import CoreHaptics

@MainActor
final class Haptics {
    private var engine: CHHapticEngine?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        try? engine?.start()
    }

    func tick() {
        guard let engine else { return }
        let ev = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
            ],
            relativeTime: 0)
        if let pattern = try? CHHapticPattern(events: [ev], parameters: []),
           let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: 0)
        }
    }
}
