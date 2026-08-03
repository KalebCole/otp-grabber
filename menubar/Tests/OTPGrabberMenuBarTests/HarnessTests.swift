#if canImport(XCTest)
import XCTest

final class HarnessTests: XCTestCase {
    func testXCTestHarnessRuns() {
        XCTAssertTrue(true)
    }
}
#endif
