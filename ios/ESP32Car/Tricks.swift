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
/// Every trick is 5 s at base; per-action durations are editable (see TrickEditorView).
enum Tricks {
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

    // MARK: per-action durations (host-tested)
    static let durMin = 100      // ms
    static let durMax = 10000

    static func clampDur(_ ms: Int) -> Int { min(durMax, max(durMin, ms)) }

    private static func same(_ a: (t: Double, y: Double), _ t: Double, _ y: Double) -> Bool {
        abs(a.t - t) < 1e-9 && abs(a.y - y) < 1e-9
    }

    /// Distinct movements of a trick, in first-appearance order, with how many steps each spans.
    static func distinctActions(_ trick: Trick) -> [(t: Double, y: Double, count: Int)] {
        var order: [(t: Double, y: Double)] = []
        var counts: [Int] = []
        for s in trick.steps {
            if let i = order.firstIndex(where: { same($0, s.t, s.y) }) { counts[i] += 1 }
            else { order.append((s.t, s.y)); counts.append(1) }
        }
        return zip(order, counts).map { ($0.t, $0.y, $1) }
    }

    /// Base duration (ms) of each distinct action.
    static func baseDurations(_ trick: Trick) -> [Int] {
        distinctActions(trick).map { a in
            trick.steps.first(where: { same((a.t, a.y), $0.t, $0.y) })?.ms ?? durMin
        }
    }

    /// Rebuild the timeline: same order/count as the base, each step's ms = the (clamped)
    /// duration of its action. Wrong-length `durs` → the base trick unchanged.
    static func withDurations(_ trick: Trick, _ durs: [Int]) -> Trick {
        let acts = distinctActions(trick)
        guard durs.count == acts.count else { return trick }
        let steps = trick.steps.map { s -> TrickStep in
            let i = acts.firstIndex(where: { same(($0.t, $0.y), s.t, s.y) }) ?? 0
            return TrickStep(t: s.t, y: s.y, ms: clampDur(durs[i]))
        }
        return Trick(id: trick.id, nameKey: trick.nameKey, icon: trick.icon, steps: steps)
    }

    /// Movement signs for labeling: fwd ∈ {-1,0,1} (back/none/forward), turn ∈ {-1,0,1} (left/none/right).
    static func actionDescriptor(_ t: Double, _ y: Double) -> (fwd: Int, turn: Int) {
        let e = 0.05
        return (t > e ? 1 : (t < -e ? -1 : 0), y > e ? 1 : (y < -e ? -1 : 0))
    }
}
