import Foundation

/// Per-trick duration multiplier, persisted in UserDefaults (tricks are app-side data).
enum TrickSettings {
    private static func key(_ id: Int) -> String { "trick.scale.\(id)" }

    static func scale(_ id: Int) -> Double {
        let v = UserDefaults.standard.object(forKey: key(id)) as? Double
        return Tricks.clampScale(v ?? 1.0)
    }
    static func setScale(_ id: Int, _ value: Double) {
        UserDefaults.standard.set(Tricks.clampScale(value), forKey: key(id))
    }
    static func reset(_ id: Int) { setScale(id, 1.0) }
}
