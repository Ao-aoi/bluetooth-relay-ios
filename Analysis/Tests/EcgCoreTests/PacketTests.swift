import XCTest
@testable import EcgCore

final class PacketTests: XCTestCase {
    func testDecode() {
        var b: [UInt8] = [1, 2, 3, 64]
        for _ in 0..<50 { b += [0x00, 0x20] }   // 0x2000 = 8192
        let p = EcgPacket(b)!
        XCTAssertEqual(p.seconds, 3600 + 120 + 3 + 0.25)
        XCTAssertEqual(p.samples.count, 50)
        XCTAssertEqual(p.samples[0], 8192)
    }
}
