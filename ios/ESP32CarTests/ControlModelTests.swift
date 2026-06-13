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
    func testTrajectoryNeverLoops() {
        // extreme small-t / large-y must stay a gentle arc, never curl back (y strictly decreasing)
        let ex = ControlModel.trajectoryPoints(t: 0.08, y: 1, length: 120, steps: 24)
        for i in 1..<ex.count { XCTAssertLessThan(ex[i].y, ex[i - 1].y) }
    }
    func testCalibSaveBody() {
        let a: [Corner: (pair: Int, sign: Int)] = [.fl: (0, 1), .fr: (1, -1), .rl: (2, 1), .rr: (3, -1)]
        XCTAssertEqual(ControlModel.calibSaveBody(a), "0:1,1:-1,2:1,3:-1")
    }
    func testSignalLevel() {
        XCTAssertEqual(ControlModel.signalLevel(online: false, pingMs: 10), 0)
        XCTAssertEqual(ControlModel.signalLevel(online: true, pingMs: nil), 0)
        XCTAssertEqual(ControlModel.signalLevel(online: true, pingMs: 10), 4)
        XCTAssertEqual(ControlModel.signalLevel(online: true, pingMs: 100), 3)
        XCTAssertEqual(ControlModel.signalLevel(online: true, pingMs: 200), 2)
        XCTAssertEqual(ControlModel.signalLevel(online: true, pingMs: 400), 1)
    }
    func testSignalLevelRssi() {
        XCTAssertEqual(ControlModel.signalLevel(online: true, rssi: -45, pingMs: 500), 4)
        XCTAssertEqual(ControlModel.signalLevel(online: true, rssi: -55, pingMs: 500), 3)
        XCTAssertEqual(ControlModel.signalLevel(online: true, rssi: -65, pingMs: 500), 2)
        XCTAssertEqual(ControlModel.signalLevel(online: true, rssi: -80, pingMs: 10), 1)
        XCTAssertEqual(ControlModel.signalLevel(online: true, rssi: nil, pingMs: 10), 4)
        XCTAssertEqual(ControlModel.signalLevel(online: false, rssi: -45, pingMs: 10), 0)
    }
    func testTelemetryParse() {
        let ok = Telemetry.parse("{\"rssi\":-55,\"ws_fps\":10,\"wdt_trips\":2,\"uptime_s\":123,\"heap\":198000,\"calibrated\":true}")!
        XCTAssertEqual(ok.rssi, -55); XCTAssertEqual(ok.uptimeS, 123); XCTAssertEqual(ok.calibrated, true)
        XCTAssertNil(Telemetry.parse("{\"rssi\":0}")!.rssi)
        XCTAssertNil(Telemetry.parse("nope"))
        XCTAssertNil(Telemetry.parse("{\"foo\":1}"))
    }
}
