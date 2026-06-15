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
}
