import Testing
import Foundation
@testable import Adapters

@Suite struct HTTPClientTypesTests {
    @Test func httpClientErrorEquality() {
        let a = HTTPClientError.transport("timeout")
        let b = HTTPClientError.transport("timeout")
        let c = HTTPClientError.statusCode(500)
        #expect(a == b)
        #expect(a != c)
    }
}
