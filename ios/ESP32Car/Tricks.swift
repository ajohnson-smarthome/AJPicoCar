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
/// Timings are starting values; tune in Swift (no firmware reflash needed).
enum Tricks {
    static let spin = Trick(id: 1, nameKey: "tricks.spin", icon: "arrow.clockwise",
                            steps: [TrickStep(t: 0, y: 1, ms: 6000)])
    static let figure8 = Trick(id: 2, nameKey: "tricks.figure8", icon: "infinity",
                               steps: [TrickStep(t: 0.6, y: 0.6, ms: 7000),
                                       TrickStep(t: 0.6, y: -0.6, ms: 7000)])
    static let wiggle = Trick(id: 3, nameKey: "tricks.wiggle", icon: "wind",
                              steps: [TrickStep(t: 0, y: 0.8, ms: 1250), TrickStep(t: 0, y: -0.8, ms: 1250),
                                      TrickStep(t: 0, y: 0.8, ms: 1250), TrickStep(t: 0, y: -0.8, ms: 1250),
                                      TrickStep(t: 0, y: 0.8, ms: 1250), TrickStep(t: 0, y: -0.8, ms: 1250)])
    static let donut = Trick(id: 4, nameKey: "tricks.donut", icon: "circle.dashed",
                             steps: [TrickStep(t: 0.7, y: 1, ms: 10000)])

    static let all: [Trick] = [spin, figure8, wiggle, donut]
}
