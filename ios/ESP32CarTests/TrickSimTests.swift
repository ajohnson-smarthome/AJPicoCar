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
        let d = Tricks.donutSides(diameterCm: 50)
        XCTAssertEqual(d.t, 0.794, accuracy: 0.01)
        XCTAssertEqual(d.y, 0.206, accuracy: 0.01)
        for diaCm in [30.0, 60.0, 120.0] {
            let s = Tricks.donutSides(diameterCm: diaCm)
            let sides = ControlModel.sides(t: s.t, y: s.y)
            let R = Tricks.donutTrackM * (sides.left + sides.right) / (2 * (sides.left - sides.right))
            XCTAssertEqual(R, diaCm / 100 / 2, accuracy: 0.005)
        }
        let tight = Tricks.donutSides(diameterCm: 5)
        XCTAssertEqual(tight.t, 0.5, accuracy: 1e-9)
        XCTAssertEqual(tight.y, 0.5, accuracy: 1e-9)
    }
    func testDonutTrick() {
        let t = Tricks.donutTrick(diameterCm: 50)
        XCTAssertEqual(t.id, Tricks.donut.id)
        XCTAssertEqual(t.steps.count, 1)
        XCTAssertEqual(t.totalMs, 5000)
    }
    func testDonutCirclesRoundTrip() {
        for v in [0.4, 0.578, 0.9] {
            for diaCm in [30.0, 50.0, 120.0] {
                for n in [1, 2, 5] {
                    let trick = Tricks.donutTrick(diameterCm: diaCm, circles: n, vmaxMS: v)
                    let r = TrickSim.simulate(steps: trick.steps, vmaxMS: v, trackM: Tricks.donutTrackM,
                                              carLenM: 0.25, carWidM: 0.15)
                    XCTAssertEqual(r.turnRad / (2 * Double.pi), Double(n), accuracy: 0.05)
                }
            }
        }
    }
    func testDonutDurationGuards() {
        let y50 = Tricks.donutSides(diameterCm: 50).y
        XCTAssertEqual(Tricks.donutDurationMs(circles: 2, y: y50, vmaxMS: Tricks.donutNominalVmaxMS), 6848)
        XCTAssertEqual(Tricks.donutDurationMs(circles: 2, y: 0.2, vmaxMS: 0), 0)
        XCTAssertEqual(Tricks.donutDurationMs(circles: 2, y: 0, vmaxMS: 0.5), 0)
        XCTAssertEqual(Tricks.donutDurationMs(circles: 0, y: 0.2, vmaxMS: 0.5),
                       Tricks.donutDurationMs(circles: 1, y: 0.2, vmaxMS: 0.5))
    }
    func testDonutTrickCircles() {
        let t = Tricks.donutTrick(diameterCm: 50, circles: 2, vmaxMS: 0.578)
        XCTAssertEqual(t.id, Tricks.donut.id)
        XCTAssertEqual(t.steps.count, 1)
    }
}
