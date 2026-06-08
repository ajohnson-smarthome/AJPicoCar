import Foundation

enum Scheme: String { case arcade, tank }

/// Pure mapping from joystick axes to the firmware's (throttle, yaw) in [-1,1].
/// Screen Y is positive downward, so "up" is a negative stick Y.
enum ControlModel {
    static func clamp(_ v: Double) -> Double { min(1, max(-1, v)) }

    /// One stick: up = throttle, left/right = yaw.
    static func arcade(stickX: Double, stickY: Double) -> (t: Double, y: Double) {
        (clamp(-stickY), clamp(stickX))
    }

    /// Two vertical sticks: each drives its side. side = -stickY.
    static func tank(leftStickY: Double, rightStickY: Double) -> (t: Double, y: Double) {
        let l = -leftStickY, r = -rightStickY
        return (clamp((l + r) / 2), clamp((l - r) / 2))
    }

    /// Mixer: throttle/yaw -> normalized left/right side speeds in [-1,1] (mirrors the firmware).
    static func sides(t: Double, y: Double) -> (left: Double, right: Double) {
        var l = t + y, r = t - y
        let m = Swift.max(abs(l), abs(r), 1)
        l /= m; r /= m
        return (l, r)
    }

    /// Wire frame "t,y" with two decimals (matches the web pad / firmware parser).
    static func frame(t: Double, y: Double) -> String {
        String(format: "%.2f,%.2f", clamp(t), clamp(y))
    }
}
