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
    // Wide donut: both wheels forward (right slower) → the car drives a visible ~0.5 m circle
    // rather than pivoting in place. (t=0.8,y=0.2 → sides 1.0/0.6 → turn radius ≈ 2·track.)
    static let donut = Trick(id: 4, nameKey: "tricks.donut", icon: "circle.dashed",
                             steps: [TrickStep(t: 0.8, y: 0.2, ms: 5000)])

    static let all: [Trick] = [spin, figure8, wiggle, donut]

    // MARK: donut geometry (pure, host-tested) — radius depends only on the side ratio + track,
    // not on motor speed. Inverse of TrickSim's R = T·(l+r)/(2(l−r)).
    /// Track width (lateral wheel separation), shared with the simulation.
    static let donutTrackM = 0.13
    static let donutDiaMinCm = 20, donutDiaMaxCm = 150, donutDiaDefaultCm = 50

    /// For a target circle diameter, hold the fast wheel at full power and solve the slow wheel's
    /// ratio, returning the (t, y) command. r is clamped to [0, 0.9] so both wheels stay forward
    /// (the maneuver remains a circle, never a pivot or near-straight line).
    static func donutSides(diameterCm: Double) -> (t: Double, y: Double) {
        let R = Swift.max(0.001, diameterCm / 100 / 2)
        let T = donutTrackM
        var r = (2 * R - T) / (2 * R + T)
        r = Swift.min(0.9, Swift.max(0.0, r))
        return ((1 + r) / 2, (1 - r) / 2)
    }

    /// The donut maneuver for a given circle diameter — same id/name/icon, the single step's
    /// (t, y) derived from `donutSides`. Real duration is layered on by `withDurations`.
    static func donutTrick(diameterCm: Double) -> Trick {
        let (t, y) = donutSides(diameterCm: diameterCm)
        return Trick(id: donut.id, nameKey: donut.nameKey, icon: donut.icon,
                     steps: [TrickStep(t: t, y: y, ms: 5000)])
    }

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
