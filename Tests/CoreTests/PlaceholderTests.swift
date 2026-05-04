import XCTest
@testable import Core

final class PlaceholderTests: XCTestCase {
    func testVersionPresent() {
        XCTAssertFalse(CoreModule.version.isEmpty)
    }
}
