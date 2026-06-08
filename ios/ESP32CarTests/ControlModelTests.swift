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
}
