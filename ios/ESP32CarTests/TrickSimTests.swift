import XCTest
@testable import ESP32Car

final class TrickSimTests: XCTestCase {
    func testStraightLine() {
        let r = TrickSim.simulate(steps: [TrickStep(t: 1, y: 0, ms: 1000)],
                                  vmaxMS: 1, trackM: 0.15, carLenM: 0.25, carWidM: 0.15)
        XCTAssertEqual(r.pathLenM, 1.0, accuracy: 0.02)
        XCTAssertEqual(r.turnRad, 0.0, accuracy: 0.01)
        XCTAssertEqual(r.areaWM, 1.25, accuracy: 0.03)
        XCTAssertEqual(r.areaHM, 0.15, accuracy: 0.01)
    }
    func testSpinInPlace() {
        let r = TrickSim.simulate(steps: [TrickStep(t: 0, y: 1, ms: 1000)],
                                  vmaxMS: 1, trackM: 0.15, carLenM: 0.25, carWidM: 0.15)
        XCTAssertEqual(r.pathLenM, 0.0, accuracy: 0.01)
        XCTAssertEqual(r.turnRad, 2.0 / 0.15, accuracy: 0.2)
    }
    func testDonutCurves() {
        let r = TrickSim.simulate(steps: [TrickStep(t: 0.7, y: 1, ms: 1000)],
                                  vmaxMS: 1, trackM: 0.15, carLenM: 0.25, carWidM: 0.15)
        XCTAssertTrue(r.pathLenM > 0.3 && r.pathLenM < 0.5)
        XCTAssertTrue(r.turnRad > 6 && r.turnRad < 9)
        XCTAssertGreaterThan(r.poses.count, 5)
    }
    func testDonutSidesRoundTrip() {
        let T = Tricks.donutTrackFallbackM
        let d = Tricks.donutSides(diameterCm: 50, trackM: T)
        XCTAssertEqual(d.t, 0.794, accuracy: 0.01)
        XCTAssertEqual(d.y, 0.206, accuracy: 0.01)
        for diaCm in [30.0, 60.0, 120.0] {
            let s = Tricks.donutSides(diameterCm: diaCm, trackM: T)
            let sides = ControlModel.sides(t: s.t, y: s.y)
            let R = T * (sides.left + sides.right) / (2 * (sides.left - sides.right))
            XCTAssertEqual(R, diaCm / 100 / 2, accuracy: 0.005)
        }
    }
    func testDonutTrackSensitivity() {
        XCTAssertNotEqual(Tricks.donutSides(diameterCm: 50, trackM: 0.10).y,
                          Tricks.donutSides(diameterCm: 50, trackM: 0.13).y)
        for tk in [0.10, 0.13, 0.16] {
            let s = Tricks.donutSides(diameterCm: 60, trackM: tk)
            let sides = ControlModel.sides(t: s.t, y: s.y)
            let R = tk * (sides.left + sides.right) / (2 * (sides.left - sides.right))
            XCTAssertEqual(R, 0.30, accuracy: 0.01)
        }
    }
    func testDonutCirclesRoundTrip() {
        for v in [0.4, 0.578, 0.9] {
            for diaCm in [30.0, 50.0, 120.0] {
                for n in [1, 2, 5] {
                    let trick = Tricks.donutTrick(diameterCm: diaCm, circles: n, vmaxMS: v,
                                                  trackM: Tricks.donutTrackFallbackM)
                    let r = TrickSim.simulate(steps: trick.steps, vmaxMS: v,
                                              trackM: Tricks.donutTrackFallbackM, carLenM: 0.25, carWidM: 0.15)
                    XCTAssertEqual(r.turnRad / (2 * Double.pi), Double(n), accuracy: 0.05)
                }
            }
        }
    }
    func testDonutDurationGuards() {
        let T = Tricks.donutTrackFallbackM
        let y50 = Tricks.donutSides(diameterCm: 50, trackM: T).y
        XCTAssertEqual(Tricks.donutDurationMs(circles: 2, y: y50, vmaxMS: Tricks.donutNominalVmaxMS, trackM: T), 6848)
        XCTAssertEqual(Tricks.donutDurationMs(circles: 2, y: 0.2, vmaxMS: 0, trackM: T), 0)
        XCTAssertEqual(Tricks.donutDurationMs(circles: 2, y: 0, vmaxMS: 0.5, trackM: T), 0)
        XCTAssertEqual(Tricks.donutDurationMs(circles: 1, y: 0.2, vmaxMS: 0.5, trackM: 0.26),
                       2 * Tricks.donutDurationMs(circles: 1, y: 0.2, vmaxMS: 0.5, trackM: 0.13))
    }
    func testDonutTrickCircles() {
        let T = Tricks.donutTrackFallbackM
        let t = Tricks.donutTrick(diameterCm: 50, circles: 2, vmaxMS: 0.578, trackM: T)
        XCTAssertEqual(t.id, Tricks.donut.id)
        XCTAssertEqual(t.steps.count, 1)
        XCTAssertEqual(t.steps[0].ms,
                       Tricks.donutDurationMs(circles: 2, y: t.steps[0].y, vmaxMS: 0.578, trackM: T))
    }
    func testSpinSpeedFormula() {
        let T = Tricks.donutTrackFallbackM, V = Tricks.donutNominalVmaxMS
        XCTAssertEqual(Tricks.spinSpeed(turns: 1, durationMs: 5000, vmaxMS: V, trackM: T), 0.141, accuracy: 0.005)
        XCTAssertEqual(Tricks.spinSpeed(turns: 2, durationMs: 5000, vmaxMS: V, trackM: T),
                       2 * Tricks.spinSpeed(turns: 1, durationMs: 5000, vmaxMS: V, trackM: T), accuracy: 1e-9)
        XCTAssertEqual(Tricks.spinSpeed(turns: 1, durationMs: 10000, vmaxMS: V, trackM: T),
                       0.5 * Tricks.spinSpeed(turns: 1, durationMs: 5000, vmaxMS: V, trackM: T), accuracy: 1e-9)
        XCTAssertEqual(Tricks.spinSpeed(turns: 6, durationMs: 1000, vmaxMS: V, trackM: T), 1.0)
        XCTAssertEqual(Tricks.spinSpeed(turns: 1, durationMs: 0, vmaxMS: V, trackM: T), 0)
        XCTAssertEqual(Tricks.spinSpeed(turns: 1, durationMs: 5000, vmaxMS: 0, trackM: T), 0)
    }
    func testSpinRoundTrip() {
        let T = Tricks.donutTrackFallbackM, V = Tricks.donutNominalVmaxMS
        for n in [1, 2, 3] {
            let trick = Tricks.spinTrick(turns: n, durationMs: 5000, vmaxMS: V, trackM: T)
            let r = TrickSim.simulate(steps: trick.steps, vmaxMS: V, trackM: T, carLenM: 0.25, carWidM: 0.15)
            XCTAssertEqual(r.turnRad / (2 * Double.pi), Double(n), accuracy: 0.05)
            XCTAssertEqual(r.pathLenM, 0.0, accuracy: 0.01)
        }
    }
    func testSpinTrick() {
        let t = Tricks.spinTrick(turns: 2, durationMs: 3000, vmaxMS: Tricks.donutNominalVmaxMS,
                                 trackM: Tricks.donutTrackFallbackM)
        XCTAssertEqual(t.id, Tricks.spin.id)
        XCTAssertEqual(t.steps.count, 1)
        XCTAssertEqual(t.steps[0].ms, 3000)
        XCTAssertEqual(t.steps[0].t, 0)
    }
}
