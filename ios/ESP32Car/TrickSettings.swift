import Foundation

/// Per-trick action durations (ms, one per distinct action), persisted in UserDefaults.
enum TrickSettings {
    private static func key(_ id: Int) -> String { "trick.durs.\(id)" }

    static func durations(for trick: Trick) -> [Int] {
        let base = Tricks.baseDurations(trick)
        if let saved = UserDefaults.standard.array(forKey: key(trick.id)) as? [Int], saved.count == base.count {
            return saved.map { Tricks.clampDur($0) }
        }
        return base
    }
    static func setDuration(_ trick: Trick, action i: Int, ms: Int) {
        var d = durations(for: trick)
        guard d.indices.contains(i) else { return }
        d[i] = Tricks.clampDur(ms)
        UserDefaults.standard.set(d, forKey: key(trick.id))
    }
    static func reset(_ trick: Trick, action i: Int) {
        var d = durations(for: trick)
        let base = Tricks.baseDurations(trick)
        guard d.indices.contains(i) else { return }
        d[i] = base[i]
        if d == base { UserDefaults.standard.removeObject(forKey: key(trick.id)) }
        else { UserDefaults.standard.set(d, forKey: key(trick.id)) }
    }

    private static let donutDiaKey = "trick.donut.diaCm"
    private static func clampDia(_ cm: Int) -> Int {
        Swift.min(Tricks.donutDiaMaxCm, Swift.max(Tricks.donutDiaMinCm, cm))
    }
    static func donutDiameterCm() -> Int {
        clampDia(UserDefaults.standard.object(forKey: donutDiaKey) as? Int ?? Tricks.donutDiaDefaultCm)
    }
    static func setDonutDiameter(_ cm: Int) {
        UserDefaults.standard.set(clampDia(cm), forKey: donutDiaKey)
    }
    static func resetDonutDiameter() {
        UserDefaults.standard.removeObject(forKey: donutDiaKey)
    }
}
