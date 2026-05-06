import XCTest
import FFmpegAutoCore
@testable import FFmpegAutoServer

final class TrimCommandBuilderTests: XCTestCase {
    private let inputURL = URL(fileURLWithPath: "/tmp/in.mp4")
    private let outputFolder = URL(fileURLWithPath: "/tmp/out")
    private let ffmpegURL = URL(fileURLWithPath: "/usr/bin/ffmpeg")
    private let outputPattern = URL(fileURLWithPath: "/tmp/out/clip_%03d.m4a")

    private func makeConversion(
        trimStart: Double? = nil,
        trimEnd: Double? = nil
    ) -> ValidatedConversion {
        var settings = AudioConversionSettings.transcriptionDefault
        settings.trimStartSeconds = trimStart
        settings.trimEndSeconds = trimEnd
        return ValidatedConversion(
            inputFile: inputURL,
            outputFolder: outputFolder,
            segmentMinutes: 1,
            ffmpegExecutableURL: ffmpegURL,
            outputPattern: outputPattern,
            settings: settings,
            extraFFmpegArguments: [],
            trimStartSeconds: trimStart,
            trimEndSeconds: trimEnd
        )
    }

    func test_noTrim_buildsClassicCommand() {
        let conversion = makeConversion()
        let args = FFmpegCommandBuilder().build(from: conversion).arguments
        XCTAssertEqual(args.first, "-i")
        XCTAssertEqual(args[1], inputURL.path)
        XCTAssertFalse(args.contains("-ss"))
        XCTAssertFalse(args.contains("-to"))
    }

    func test_trimStartOnly_addsSsBeforeInput() {
        let conversion = makeConversion(trimStart: 12.5)
        let args = FFmpegCommandBuilder().build(from: conversion).arguments
        XCTAssertEqual(args[0], "-ss")
        XCTAssertEqual(args[1], "12.500")
        XCTAssertEqual(args[2], "-i")
        XCTAssertEqual(args[3], inputURL.path)
        XCTAssertFalse(args.contains("-to"))
    }

    func test_trimEndOnly_addsToBeforeInput() {
        let conversion = makeConversion(trimEnd: 90.25)
        let args = FFmpegCommandBuilder().build(from: conversion).arguments
        XCTAssertEqual(args[0], "-to")
        XCTAssertEqual(args[1], "90.250")
        XCTAssertEqual(args[2], "-i")
        XCTAssertEqual(args[3], inputURL.path)
    }

    func test_bothTrim_ssAndToBothBeforeInput() {
        let conversion = makeConversion(trimStart: 30, trimEnd: 90)
        let args = FFmpegCommandBuilder().build(from: conversion).arguments
        XCTAssertEqual(args[0], "-ss")
        XCTAssertEqual(args[1], "30.000")
        XCTAssertEqual(args[2], "-to")
        XCTAssertEqual(args[3], "90.000")
        XCTAssertEqual(args[4], "-i")
        XCTAssertEqual(args[5], inputURL.path)
        let toIndex = args.firstIndex(of: "-to")!
        let inputIndex = args.firstIndex(of: "-i")!
        XCTAssertLessThan(toIndex, inputIndex, "-to must precede -i so it acts as input option")
    }

    func test_trimStartZero_omitsSsFlag() {
        let conversion = makeConversion(trimStart: 0, trimEnd: 60)
        let args = FFmpegCommandBuilder().build(from: conversion).arguments
        XCTAssertFalse(args.contains("-ss"))
        XCTAssertTrue(args.contains("-to"))
        let toIndex = args.firstIndex(of: "-to")!
        let inputIndex = args.firstIndex(of: "-i")!
        XCTAssertLessThan(toIndex, inputIndex)
    }

    func test_subSecondPrecision_formatsThreeDecimals() {
        XCTAssertEqual(FFmpegCommandBuilder.formatTimestamp(0.001), "0.001")
        XCTAssertEqual(FFmpegCommandBuilder.formatTimestamp(123.456789), "123.457")
        XCTAssertEqual(FFmpegCommandBuilder.formatTimestamp(60), "60.000")
    }
}
