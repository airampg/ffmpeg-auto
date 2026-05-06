import XCTest
@testable import FFmpegAutoServer

final class ProgressParserTests: XCTestCase {
    func testExtractTimeFromTypicalLine() throws {
        let value = try XCTUnwrap(ProgressParser.extractTime(from: "size=  176kB time=00:01:23.45 bitrate= 24.1kbits/s"))
        XCTAssertEqual(value, 83.45, accuracy: 0.001)
    }

    func testExtractTimeMissingReturnsNil() {
        XCTAssertNil(ProgressParser.extractTime(from: "ffmpeg version 6.1.1"))
    }

    func testIngestSplitsOnCarriageReturn() {
        var parser = ProgressParser()
        let chunk = "size=N/A time=00:00:01.50 bitrate=N/A\rsize=N/A time=00:00:02.10 bitrate=N/A\r"
        let times = parser.ingest(chunk)
        XCTAssertEqual(times.count, 2)
        XCTAssertEqual(times[0], 1.5, accuracy: 0.001)
        XCTAssertEqual(times[1], 2.1, accuracy: 0.001)
    }

    func testIngestCarriesPartialLineForward() {
        var parser = ProgressParser()
        let part1 = parser.ingest("size=N/A time=00:00:0")
        XCTAssertTrue(part1.isEmpty)
        let part2 = parser.ingest("3.50 bitrate=N/A\n")
        XCTAssertEqual(part2.first, 3.5)
    }
}
