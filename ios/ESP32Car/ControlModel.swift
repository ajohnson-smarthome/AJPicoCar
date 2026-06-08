import Foundation
import CoreGraphics

enum Scheme: String { case arcade, tank }

enum DiagramState { case idle, drive, spin }

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

    /// Which visual the diagram shows for a command.
    static func diagramState(t: Double, y: Double) -> DiagramState {
        if abs(t) >= 0.05 { return .drive }
        if abs(y) >= 0.05 { return .spin }
        return .idle
    }

    /// Signed path curvature ~ yaw / speed (bounded near t=0).
    static func curvature(t: Double, y: Double) -> Double {
        y / Swift.max(abs(t), 0.15)
    }

    /// Centerline of the predicted path in local space: starts at (0,0), heads "up"
    /// (screen -y), bends by yaw. Caller offsets/positions for the two rails.
    static func trajectoryPoints(t: Double, y: Double, length: Double, steps: Int) -> [CGPoint] {
        let curv = curvature(t: t, y: y)
        let seg = length / Double(steps)
        var pts: [CGPoint] = []
        var x = 0.0, yy = 0.0
        var heading = -Double.pi / 2
        for _ in 0...steps {
            pts.append(CGPoint(x: x, y: yy))
            heading += curv * seg * 0.045
            x += Foundation.cos(heading) * seg
            yy += Foundation.sin(heading) * seg
        }
        return pts
    }
}
