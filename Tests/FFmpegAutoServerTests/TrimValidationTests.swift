import XCTest
import FFmpegAutoCore
@testable import FFmpegAutoServer

final class TrimValidationTests: XCTestCase {
    private let validator = ValidationService()

    private func settings(start: Double? = nil, end: Double? = nil) -> AudioConversionSettings {
        var s = AudioConversionSettings.transcriptionDefault
        s.trimStartSeconds = start
        s.trimEndSeconds = end
        return s
    }

    func test_noTrim_passes() {
        XCTAssertNoThrow(try validator.validateTrim(settings: settings(), probedDuration: nil))
    }

    func test_negativeStart_throws() {
        XCTAssertThrowsError(try validator.validateTrim(settings: settings(start: -1), probedDuration: nil)) { error in
            XCTAssertEqual(error as? AppValidationError, .trimStartNegative)
        }
    }

    func test_endNotAfterStart_throws() {
        XCTAssertThrowsError(try validator.validateTrim(settings: settings(start: 30, end: 30), probedDuration: nil)) { error in
            XCTAssertEqual(error as? AppValidationError, .trimEndNotAfterStart)
        }
        XCTAssertThrowsError(try validator.validateTrim(settings: settings(start: 30, end: 20), probedDuration: nil)) { error in
            XCTAssertEqual(error as? AppValidationError, .trimEndNotAfterStart)
        }
    }

    func test_rangeTooShort_throws() {
        XCTAssertThrowsError(try validator.validateTrim(settings: settings(start: 0, end: 0.5), probedDuration: nil)) { error in
            if case .trimRangeTooShort = error as? AppValidationError {
                return
            }
            XCTFail("Expected trimRangeTooShort, got \(error)")
        }
    }

    func test_validRange_passes() {
        XCTAssertNoThrow(try validator.validateTrim(settings: settings(start: 0, end: 1.0), probedDuration: nil))
        XCTAssertNoThrow(try validator.validateTrim(settings: settings(start: 10, end: 70), probedDuration: nil))
    }

    func test_endBeyondProbedDuration_throws() {
        XCTAssertThrowsError(try validator.validateTrim(settings: settings(start: 0, end: 100), probedDuration: 60)) { error in
            if case .trimEndBeyondDuration = error as? AppValidationError {
                return
            }
            XCTFail("Expected trimEndBeyondDuration, got \(error)")
        }
    }

    func test_endWithinTolerance_passes() {
        XCTAssertNoThrow(try validator.validateTrim(settings: settings(start: 0, end: 60.3), probedDuration: 60))
    }
}

final class TrimDTORoundtripTests: XCTestCase {
    func test_decodeWithoutTrimFields_succeedsAndProducesNilTrim() throws {
        let json = """
        {
          "segmentMinutes": 5,
          "codec": "aac",
          "container": "m4a",
          "bitrate": "48k",
          "sampleRate": 16000,
          "channels": 1
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(JobSubmitDTO.self, from: json)
        XCTAssertNil(dto.trimStartSeconds)
        XCTAssertNil(dto.trimEndSeconds)
        let settings = try dto.toSettings()
        XCTAssertNil(settings.trimStartSeconds)
        XCTAssertNil(settings.trimEndSeconds)
    }

    func test_decodeWithTrimFields_preservesValues() throws {
        let json = """
        {
          "segmentMinutes": 5,
          "codec": "aac",
          "container": "m4a",
          "bitrate": "48k",
          "sampleRate": 16000,
          "channels": 1,
          "trimStartSeconds": 12.5,
          "trimEndSeconds": 90.25
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(JobSubmitDTO.self, from: json)
        XCTAssertEqual(dto.trimStartSeconds, 12.5)
        XCTAssertEqual(dto.trimEndSeconds, 90.25)
        let settings = try dto.toSettings()
        XCTAssertEqual(settings.trimStartSeconds, 12.5)
        XCTAssertEqual(settings.trimEndSeconds, 90.25)
    }
}
