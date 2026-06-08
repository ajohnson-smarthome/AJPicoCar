import XCTest
@testable import ESP32Car

final class ControlModelTests: XCTestCase {
    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }

    func testArcadeForward() {
        let r = ControlModel.arcade(stickX: 0, stickY: -1)
        XCTAssertTrue(close(r.t, 1) && close(r.y, 0))
    }
    func testArcadeTurn() {
        let r = ControlModel.arcade(stickX: 1, stickY: 0)
        XCTAssertTrue(close(r.t, 0) && close(r.y, 1))
    }
    func testTankForward() {
        let r = ControlModel.tank(leftStickY: -1, rightStickY: -1)
        XCTAssertTrue(close(r.t, 1) && close(r.y, 0))
    }
    func testTankSpin() {
        let r = ControlModel.tank(leftStickY: -1, rightStickY: 1)
        XCTAssertTrue(close(r.t, 0) && close(r.y, 1))
    }
    func testClamp() {
        XCTAssertEqual(ControlModel.clamp(2.5), 1)
        XCTAssertEqual(ControlModel.clamp(-2.5), -1)
        XCTAssertEqual(ControlModel.clamp(0.3), 0.3)
    }
    func testFrame() {
        XCTAssertEqual(ControlModel.frame(t: 0.5, y: -1), "0.50,-1.00")
    }
    func testSidesForward() {
        let s = ControlModel.sides(t: 1, y: 0)
        XCTAssertTrue(close(s.left, 1) && close(s.right, 1))
    }
    func testSidesSpin() {
        let s = ControlModel.sides(t: 0, y: 1)
        XCTAssertTrue(close(s.left, 1) && close(s.right, -1))
    }
    func testSidesArcNormalized() {
        let s = ControlModel.sides(t: 0.5, y: 0.5)
        XCTAssertTrue(close(s.left, 1) && close(s.right, 0))
    }
    func testDiagramState() {
        XCTAssertEqual(ControlModel.diagramState(t: 0.8, y: 0), .drive)
        XCTAssertEqual(ControlModel.diagramState(t: 0, y: 0.7), .spin)
        XCTAssertEqual(ControlModel.diagramState(t: 0, y: 0), .idle)
    }
    func testCurvature() {
        XCTAssertEqual(ControlModel.curvature(t: 1, y: 0), 0, accuracy: 1e-9)
        XCTAssertTrue(ControlModel.curvature(t: 1, y: 0.5) > 0)
        XCTAssertTrue(ControlModel.curvature(t: 1, y: -0.5) < 0)
    }
    func testTrajectoryStraightVsCurved() {
        XCTAssertLessThan(abs(ControlModel.trajectoryPoints(t: 1, y: 0, length: 100, steps: 24).last!.x), 1e-6)
        XCTAssertGreaterThan(abs(ControlModel.trajectoryPoints(t: 1, y: 0.6, length: 100, steps: 24).last!.x), 5)
    }
}
