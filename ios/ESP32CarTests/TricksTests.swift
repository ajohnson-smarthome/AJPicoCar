import XCTest
@testable import ESP32Car

final class TricksTests: XCTestCase {
    func testAllBounded() {
        for tr in Tricks.all {
            XCTAssertFalse(tr.steps.isEmpty)
            XCTAssertTrue(tr.totalMs > 0 && tr.totalMs <= 20000)
            for s in tr.steps {
                XCTAssertTrue(s.t >= -1 && s.t <= 1 && s.y >= -1 && s.y <= 1 && s.ms > 0)
            }
        }
    }
    func testIdsUnique() {
        XCTAssertEqual(Set(Tricks.all.map { $0.id }).count, Tricks.all.count)
    }
}
