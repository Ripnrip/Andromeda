/**
 * HexEncodingTests — prove the shared digest→hex helper stays stable.
 */

import Foundation
import Testing
@testable import MemoryKit

@Suite("HexEncoding")
struct HexEncodingTests {
    @Test("hexLowercase matches the historical %02x map/join shape")
    func hexLowercaseMatchesLegacyFormat() {
        let bytes: [UInt8] = [0x00, 0x0f, 0xa1, 0xff]
        let legacy = bytes.map { String(format: "%02x", $0) }.joined()
        #expect(bytes.hexLowercase == legacy)
        #expect(bytes.hexLowercase == "000fa1ff")
    }
}
