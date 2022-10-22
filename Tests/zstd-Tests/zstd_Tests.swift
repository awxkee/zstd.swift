import XCTest
@testable import zstd

final class zstd_Tests: XCTestCase {

    func testCompression() throws {
        let testData = "Performance will only suffer significantly for very tiny buffers."
        let compressedData = try ZStd.compress(testData.data(using: .utf8)!)
        assert(compressedData.count != 0)
        let decompressedData = try ZStd.decompress(compressedData)
        assert(decompressedData.count != 0)
        let decompressedString = String(data: decompressedData, encoding: .utf8)!
        assert(decompressedString == testData, "compression and decompression must be loseless")
    }

    func testCompressionFromURLToURL() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("src")
        print(sourceURL.path)
        let testString = "Performance will only suffer significantly for very tiny buffers."
        let testData = testString.data(using: .utf8)!
        try testData.write(to: sourceURL)
        let dstURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dst.zst")
        try ZStd.compress(from: sourceURL, to: dstURL)

        let decompressedData = try ZStd.decompress(src: dstURL)
        assert(decompressedData.count != 0)
        let decompressedString = String(data: decompressedData, encoding: .utf8)!
        assert(decompressedString == testString, "compression and decompression must be loseless")

        try FileManager.default.removeItem(at: sourceURL)
        try FileManager.default.removeItem(at: dstURL)
    }

}
