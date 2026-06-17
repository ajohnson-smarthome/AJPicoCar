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

    private static let donutCirclesKey = "trick.donut.circles"
    private static func clampCircles(_ n: Int) -> Int {
        Swift.min(Tricks.donutCirclesMax, Swift.max(Tricks.donutCirclesMin, n))
    }
    static func donutCircles() -> Int {
        clampCircles(UserDefaults.standard.object(forKey: donutCirclesKey) as? Int ?? Tricks.donutCirclesDefault)
    }
    static func setDonutCircles(_ n: Int) {
        UserDefaults.standard.set(clampCircles(n), forKey: donutCirclesKey)
    }
    static func resetDonutCircles() {
        UserDefaults.standard.removeObject(forKey: donutCirclesKey)
    }

    private static let spinTurnsKey = "trick.spin.turns"
    private static func clampSpinTurns(_ n: Int) -> Int {
        Swift.min(Tricks.spinTurnsMax, Swift.max(Tricks.spinTurnsMin, n))
    }
    static func spinTurns() -> Int {
        clampSpinTurns(UserDefaults.standard.object(forKey: spinTurnsKey) as? Int ?? Tricks.spinTurnsDefault)
    }
    static func setSpinTurns(_ n: Int) {
        UserDefaults.standard.set(clampSpinTurns(n), forKey: spinTurnsKey)
    }
    static func resetSpinTurns() {
        UserDefaults.standard.removeObject(forKey: spinTurnsKey)
    }

    private static let spinDurKey = "trick.spin.durMs"
    private static func clampSpinDur(_ ms: Int) -> Int {
        Swift.min(Tricks.spinDurMaxMs, Swift.max(Tricks.spinDurMinMs, ms))
    }
    static func spinDurMs() -> Int {
        clampSpinDur(UserDefaults.standard.object(forKey: spinDurKey) as? Int ?? Tricks.spinDurDefaultMs)
    }
    static func setSpinDurMs(_ ms: Int) {
        UserDefaults.standard.set(clampSpinDur(ms), forKey: spinDurKey)
    }
    static func resetSpinDurMs() {
        UserDefaults.standard.removeObject(forKey: spinDurKey)
    }
}
