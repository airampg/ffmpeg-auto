import XCTest
@testable import FFmpegAutoServer

final class MultipartParsingTests: XCTestCase {
    func testExtractBoundary() {
        XCTAssertEqual(
            MultipartParsing.extractBoundary(from: "multipart/form-data; boundary=----WebKitFormBoundaryABC"),
            "----WebKitFormBoundaryABC"
        )
    }

    func testExtractBoundaryQuoted() {
        XCTAssertEqual(
            MultipartParsing.extractBoundary(from: "multipart/form-data; boundary=\"abc-123\""),
            "abc-123"
        )
    }

    func testExtractBoundaryMissing() {
        XCTAssertNil(MultipartParsing.extractBoundary(from: "application/json"))
    }

    func testExtractParameterFromContentDisposition() {
        let header = "form-data; name=\"file\"; filename=\"recording.mp3\""
        XCTAssertEqual(MultipartParsing.extractParameter(from: header, name: "name"), "file")
        XCTAssertEqual(MultipartParsing.extractParameter(from: header, name: "filename"), "recording.mp3")
    }

    func testSanitizeFilenameStripsTraversal() {
        XCTAssertEqual(UploadStore.sanitizeFilename("../etc/passwd"), "-/etc/passwd".replacingOccurrences(of: "/", with: "-"))
        XCTAssertEqual(UploadStore.sanitizeFilename("clean.mp3"), "clean.mp3")
        XCTAssertEqual(UploadStore.sanitizeFilename(""), "upload")
    }
}
