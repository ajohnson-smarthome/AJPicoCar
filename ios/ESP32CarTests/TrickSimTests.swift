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
}
