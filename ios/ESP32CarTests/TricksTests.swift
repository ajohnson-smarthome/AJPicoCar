import XCTest
@testable import ESP32Car

final class TricksTests: XCTestCase {
    private func approx(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    func testBaseFiveSeconds() {
        for tr in Tricks.all {
            XCTAssertFalse(tr.steps.isEmpty)
            XCTAssertEqual(tr.totalMs, 5000)
            for s in tr.steps { XCTAssertTrue(s.t >= -1 && s.t <= 1 && s.y >= -1 && s.y <= 1 && s.ms > 0) }
        }
    }
    func testIdsUnique() { XCTAssertEqual(Set(Tricks.all.map { $0.id }).count, Tricks.all.count) }
    func testClamp() {
        XCTAssertTrue(approx(Tricks.clampScale(0.1), 0.5))
        XCTAssertTrue(approx(Tricks.clampScale(99), 12))
        XCTAssertTrue(approx(Tricks.clampScale(2), 2))
    }
    func testScaled() {
        let sc = Tricks.scaled([TrickStep(t: 0.6, y: -0.6, ms: 1000)], by: 2)
        XCTAssertEqual(sc[0].ms, 2000)
        XCTAssertTrue(approx(sc[0].t, 0.6) && approx(sc[0].y, -0.6))
        XCTAssertEqual(Tricks.scaled([TrickStep(t: 0, y: 0, ms: 1)], by: 0.5)[0].ms, 1)
        XCTAssertEqual(Tricks.scaledTrick(Tricks.spin, by: 3).totalMs, 15000)
    }
    func testLogMapping() {
        XCTAssertTrue(approx(Tricks.sliderToScale(0), 0.5))
        XCTAssertTrue(approx(Tricks.sliderToScale(1), 12))
        XCTAssertTrue(approx(Tricks.sliderToScale(Tricks.scaleToSlider(3.7)), 3.7))
    }
}
