import Foundation

/// One step of a maneuver: hold (t, y) for `ms` milliseconds.
struct TrickStep { let t: Double; let y: Double; let ms: Int }

/// A named maneuver = a timeline of steps the app streams over the WS channel.
struct Trick: Identifiable {
    let id: Int            // 1..N, unique
    let nameKey: String    // Localizable key (→ L.trickName)
    let icon: String       // SF Symbol
    let steps: [TrickStep]
    var totalMs: Int { steps.reduce(0) { $0 + $1.ms } }
}

/// Open-loop (no gyro) — angles/distances are approximate and surface/battery dependent.
/// Every trick is 5 s at ×1; a per-trick multiplier (0.5–12, log slider) scales the timeline.
enum Tricks {
    static let baseMs = 5000
    static let scaleMin = 0.5
    static let scaleMax = 12.0

    static let spin = Trick(id: 1, nameKey: "tricks.spin", icon: "arrow.clockwise",
                            steps: [TrickStep(t: 0, y: 1, ms: 5000)])
    static let figure8 = Trick(id: 2, nameKey: "tricks.figure8", icon: "infinity",
                               steps: [TrickStep(t: 0.6, y: 0.6, ms: 2500),
                                       TrickStep(t: 0.6, y: -0.6, ms: 2500)])
    static let wiggle = Trick(id: 3, nameKey: "tricks.wiggle", icon: "wind",
                              steps: (0..<20).map { TrickStep(t: 0, y: $0 % 2 == 0 ? 0.8 : -0.8, ms: 250) })
    static let donut = Trick(id: 4, nameKey: "tricks.donut", icon: "circle.dashed",
                             steps: [TrickStep(t: 0.7, y: 1, ms: 5000)])

    static let all: [Trick] = [spin, figure8, wiggle, donut]

    // MARK: pure helpers (host-tested)
    static func clampScale(_ v: Double) -> Double { min(scaleMax, max(scaleMin, v)) }

    static func scaled(_ steps: [TrickStep], by scale: Double) -> [TrickStep] {
        let s = clampScale(scale)
        return steps.map { TrickStep(t: $0.t, y: $0.y, ms: max(1, Int((Double($0.ms) * s).rounded()))) }
    }

    static func scaledTrick(_ trick: Trick, by scale: Double) -> Trick {
        Trick(id: trick.id, nameKey: trick.nameKey, icon: trick.icon, steps: scaled(trick.steps, by: scale))
    }

    /// Log slider position p∈[0,1] ↔ multiplier in [scaleMin, scaleMax].
    static func sliderToScale(_ p: Double) -> Double { scaleMin * pow(scaleMax / scaleMin, min(1, max(0, p))) }
    static func scaleToSlider(_ s: Double) -> Double { log(clampScale(s) / scaleMin) / log(scaleMax / scaleMin) }
}
