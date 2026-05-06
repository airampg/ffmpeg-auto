import Foundation
import FFmpegAutoCore

@MainActor
struct TestRunner {
    private var failures: [String] = []

    mutating func run() async {
        testDurationEditingCommitAndStepperLogic()
        testDurationLiveValidDraftUpdatesWithoutEnter()
        testMinutesToSecondsConversion()
        testDefaultCommandConstruction()
        testAdvancedCommandConstruction()
        await testStartUsesLiveDurationAndAdvancedFieldsWithoutEnter()
        testCodecContainerCompatibilityValidation()
        testAdvancedLiveValidationMessages()
        testFilenamePrefixHandling()
        testLoudnormInsertion()
        testCollisionRejection()
        testFFmpegNotFoundPathReporting()
        await testSuccessPopupThenTrashPromptOrdering()
        await testTrashPromptAbsentOnFailure()

        if failures.isEmpty {
            print("All FFmpegAutoCore tests passed.")
        } else {
            print("FFmpegAutoCore tests failed:")
            failures.forEach { print("- \($0)") }
            Foundation.exit(1)
        }
    }

    mutating private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures.append(message) }
    }

    mutating private func expectValidationError(_ expected: AppValidationError, _ operation: () throws -> Any) {
        do {
            _ = try operation()
            failures.append("Expected validation error: \(expected)")
        } catch let error as AppValidationError {
            expect(error == expected, "Expected \(expected), got \(error)")
        } catch {
            failures.append("Unexpected error: \(error)")
        }
    }

    mutating private func testDurationEditingCommitAndStepperLogic() {
        let viewModel = AppViewModel(locator: MockLocator(location: FFmpegLocation(executableURL: URL(fileURLWithPath: "/bin/ffmpeg"), checkedPaths: ["/bin/ffmpeg"])))
        viewModel.segmentMinutesDraftChanged("7")
        expect(viewModel.segmentMinutes == 7, "Typed duration should commit to typed minutes")
        expect(viewModel.segmentMinutesDraft == "7", "Duration draft should preserve committed typed value")
        expect(viewModel.segmentDurationMessage.contains("420 seconds"), "Duration message should show seconds conversion")

        viewModel.segmentMinutesDraftChanged("abc")
        expect(viewModel.segmentMinutes == 7, "Invalid typed duration should not overwrite last valid typed minutes")
        expect(viewModel.segmentMinutesDraft == "abc", "Invalid draft should remain editable and not snap back")

        viewModel.setSegmentMinutes(8)
        expect(viewModel.segmentMinutes == 8, "Stepper should update typed minutes")
        expect(viewModel.segmentMinutesDraft == "8", "Stepper should sync draft text")
    }

    mutating private func testDurationLiveValidDraftUpdatesWithoutEnter() {
        let viewModel = AppViewModel(locator: MockLocator(location: FFmpegLocation(executableURL: URL(fileURLWithPath: "/bin/ffmpeg"), checkedPaths: ["/bin/ffmpeg"])))
        viewModel.segmentMinutesDraftChanged("12")
        expect(viewModel.segmentMinutes == 12, "Valid typed duration should update the committed value immediately without Enter")
        expect(viewModel.segmentDurationMessage.contains("720 seconds"), "Valid typed duration should update derived seconds immediately")
        viewModel.segmentMinutesDraftChanged("12x")
        expect(viewModel.segmentMinutes == 12, "Invalid partial duration should preserve last valid committed value")
        expect(viewModel.segmentMinutesDraft == "12x", "Invalid partial duration should remain visible for editing")
        expect(viewModel.segmentDurationMessage == "Segment length must be a whole number of minutes.", "Invalid partial duration should show live validation")
    }

    mutating private func testMinutesToSecondsConversion() {
        let conversion = ValidatedConversion(inputFile: URL(fileURLWithPath: "/tmp/in.mov"), outputFolder: URL(fileURLWithPath: "/tmp/out"), segmentMinutes: 3, ffmpegExecutableURL: URL(fileURLWithPath: "/bin/ffmpeg"), outputPattern: URL(fileURLWithPath: "/tmp/out/meetingin_%03d.m4a"))
        expect(conversion.segmentSeconds == 180, "3 minutes should convert to 180 seconds")
    }

    mutating private func testDefaultCommandConstruction() {
        let conversion = ValidatedConversion(inputFile: URL(fileURLWithPath: "/Users/me/Meeting Recordings/2026-05-06.mov"), outputFolder: URL(fileURLWithPath: "/Users/me/Chunks"), segmentMinutes: 15, ffmpegExecutableURL: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"), outputPattern: URL(fileURLWithPath: "/Users/me/Chunks/meeting2026-05-06_%03d.m4a"))
        let command = FFmpegCommandBuilder().build(from: conversion)
        expect(command.arguments == ["-i", "/Users/me/Meeting Recordings/2026-05-06.mov", "-vn", "-ac", "1", "-ar", "16000", "-c:a", "aac", "-b:a", "48k", "-f", "segment", "-segment_time", "900", "-reset_timestamps", "1", "/Users/me/Chunks/meeting2026-05-06_%03d.m4a"], "Default command should preserve transcription preset")
    }

    mutating private func testAdvancedCommandConstruction() {
        var settings = AudioConversionSettings.transcriptionDefault
        settings.codec = .mp3
        settings.container = .mp3
        settings.bitrate = "96k"
        settings.sampleRate = 44100
        settings.channelCount = .stereo
        settings.filenamePrefix = "call-"
        settings.resetTimestamps = false
        settings.collisionPolicy = .overwriteMatchingSegments
        settings.extraFFmpegArgumentsText = "-map_metadata -1"
        let conversion = ValidatedConversion(inputFile: URL(fileURLWithPath: "/tmp/Team Sync.mov"), outputFolder: URL(fileURLWithPath: "/tmp/out"), segmentMinutes: 5, ffmpegExecutableURL: URL(fileURLWithPath: "/bin/ffmpeg"), outputPattern: URL(fileURLWithPath: "/tmp/out/call-Team-Sync_%03d.mp3"), settings: settings, extraFFmpegArguments: ["-map_metadata", "-1"])
        let args = FFmpegCommandBuilder().build(from: conversion).arguments
        expect(args.contains("-y"), "Overwrite policy should add -y")
        expect(args.contains("libmp3lame"), "MP3 should map to libmp3lame")
        expect(args.contains("44100"), "Advanced sample rate should be used")
        expect(args.contains("96k"), "Advanced bitrate should be used")
        expect(!args.contains("-reset_timestamps"), "Reset timestamp flag should be omitted when disabled")
        expect(args.suffix(1).first == "/tmp/out/call-Team-Sync_%03d.mp3", "Advanced container extension should be used")
    }

    mutating private func testStartUsesLiveDurationAndAdvancedFieldsWithoutEnter() async {
        do {
            let temp = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: temp) }
            let input = temp.appendingPathComponent("Team Sync.mov")
            let output = temp.appendingPathComponent("out", isDirectory: true)
            try Data().write(to: input)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

            let locator = MockLocator(location: FFmpegLocation(executableURL: URL(fileURLWithPath: "/custom/ffmpeg"), checkedPaths: ["/custom/ffmpeg"]))
            let runner = MockRunner(result: FFmpegResult(exitCode: 0, stdout: "", stderr: ""))
            let viewModel = AppViewModel(locator: locator, runner: runner)
            viewModel.inputFile = input
            viewModel.outputFolder = output
            viewModel.segmentMinutesDraftChanged("12")
            viewModel.settings.bitrate = "128k"
            viewModel.settings.filenamePrefix = "client x "
            viewModel.settings.extraFFmpegArgumentsText = "-map_metadata -1"
            viewModel.settings.ffmpegPathOverride = "/custom/ffmpeg"
            viewModel.advancedSettingsChanged()

            await viewModel.start()

            let args = runner.receivedCommand?.arguments ?? []
            expect(locator.receivedOverridePath == "/custom/ffmpeg", "ffmpeg path override should propagate to locator without Enter")
            expect(args.contains("720"), "Live duration draft should drive -segment_time without Enter")
            expect(args.contains("128k"), "Live bitrate edit should drive command without Enter")
            expect(args.contains("-map_metadata") && args.contains("-1"), "Live extra args edit should drive command without Enter")
            expect(args.last == output.appendingPathComponent("client-xTeam-Sync_%03d.m4a").path, "Live filename prefix edit should drive output pattern without Enter")
        } catch {
            failures.append("Live field propagation integration test failed: \(error)")
        }
    }

    mutating private func testCodecContainerCompatibilityValidation() {
        var settings = AudioConversionSettings.transcriptionDefault
        settings.codec = .opus
        settings.container = .m4a
        expectValidationError(.incompatibleCodecContainer(.opus, .m4a)) {
            try ValidationService().validateAudioSettings(settings)
        }
    }

    mutating private func testAdvancedLiveValidationMessages() {
        let viewModel = AppViewModel(locator: MockLocator(location: FFmpegLocation(executableURL: URL(fileURLWithPath: "/bin/ffmpeg"), checkedPaths: ["/bin/ffmpeg"])))
        viewModel.settings.bitrate = "128kbps"
        viewModel.advancedSettingsChanged()
        expect(viewModel.advancedValidationMessage.contains("Audio bitrate must look like"), "Invalid bitrate should update advanced validation live")

        viewModel.settings.bitrate = "64k"
        viewModel.settings.filenamePrefix = "!!!"
        viewModel.advancedSettingsChanged()
        expect(viewModel.advancedValidationMessage == "Filename prefix cannot be empty after sanitising. Use a simple prefix such as meeting.", "Invalid prefix should update advanced validation live")

        viewModel.settings.filenamePrefix = "meeting"
        viewModel.settings.extraFFmpegArgumentsText = "\"unterminated"
        viewModel.advancedSettingsChanged()
        expect(viewModel.advancedValidationMessage == "Custom FFmpeg arguments are invalid: Unclosed quote.", "Invalid extra args should update advanced validation live")

        viewModel.settings.extraFFmpegArgumentsText = ""
        viewModel.advancedSettingsChanged()
        expect(viewModel.advancedValidationMessage.contains("Advanced settings look valid"), "Valid advanced settings should clear validation warning")
    }

    mutating private func testFilenamePrefixHandling() {
        var settings = AudioConversionSettings.transcriptionDefault
        settings.filenamePrefix = "client call "
        let pattern = FileNamingService().outputPattern(inputFile: URL(fileURLWithPath: "/tmp/Team Sync.mov"), outputFolder: URL(fileURLWithPath: "/tmp/out"), settings: settings)
        expect(pattern.lastPathComponent == "client-callTeam-Sync_%03d.m4a", "Filename prefix should be sanitised and combined with input stem")
    }

    mutating private func testLoudnormInsertion() {
        var settings = AudioConversionSettings.transcriptionDefault
        settings.loudnessNormalizationEnabled = true
        let conversion = ValidatedConversion(inputFile: URL(fileURLWithPath: "/tmp/in.mov"), outputFolder: URL(fileURLWithPath: "/tmp/out"), segmentMinutes: 1, ffmpegExecutableURL: URL(fileURLWithPath: "/bin/ffmpeg"), outputPattern: URL(fileURLWithPath: "/tmp/out/meetingin_%03d.m4a"), settings: settings)
        let args = FFmpegCommandBuilder().build(from: conversion).arguments
        expect(args.contains("-af"), "loudnorm should add -af")
        expect(args.contains("loudnorm=I=-16:TP=-1.5:LRA=11"), "loudnorm filter should be inserted")
    }

    mutating private func testCollisionRejection() {
        do {
            let temp = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: temp) }
            let input = temp.appendingPathComponent("2026-05-06.mov")
            let output = temp.appendingPathComponent("out", isDirectory: true)
            try Data().write(to: input)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try Data().write(to: output.appendingPathComponent("meeting2026-05-06_000.m4a"))
            expectValidationError(.existingOutputFiles("meeting2026-05-06", "m4a")) {
                try ValidationService().validate(ValidationContext(inputFile: input, outputFolder: output, segmentMinutesText: "15", ffmpegLocation: FFmpegLocation(executableURL: URL(fileURLWithPath: "/bin/ffmpeg"), checkedPaths: ["/bin/ffmpeg"])))
            }
        } catch {
            failures.append("Collision rejection setup failed: \(error)")
        }
    }

    mutating private func testFFmpegNotFoundPathReporting() {
        expectValidationError(.missingFFmpeg(checkedPaths: ["/missing/ffmpeg", "/opt/homebrew/bin/ffmpeg"])) {
            let temp = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: temp) }
            let input = temp.appendingPathComponent("in.mov")
            let output = temp.appendingPathComponent("out", isDirectory: true)
            try Data().write(to: input)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            return try ValidationService().validate(ValidationContext(inputFile: input, outputFolder: output, segmentMinutesText: "15", ffmpegLocation: FFmpegLocation(executableURL: nil, checkedPaths: ["/missing/ffmpeg", "/opt/homebrew/bin/ffmpeg"])))
        }
    }

    mutating private func testSuccessPopupThenTrashPromptOrdering() async {
        do {
            let temp = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: temp) }
            let input = temp.appendingPathComponent("recording.mov")
            let output = temp.appendingPathComponent("out", isDirectory: true)
            try Data().write(to: input)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let finder = MockFinder()
            let trash = MockTrash()
            let runner = MockRunner(result: FFmpegResult(exitCode: 0, stdout: "", stderr: "")) {
                try? Data().write(to: output.appendingPathComponent("meetingrecording_000.m4a"))
            }
            let viewModel = AppViewModel(locator: MockLocator(location: FFmpegLocation(executableURL: URL(fileURLWithPath: "/bin/ffmpeg"), checkedPaths: ["/bin/ffmpeg"])), runner: runner, finder: finder, trash: trash)
            viewModel.inputFile = input
            viewModel.outputFolder = output
            await viewModel.start()
            expect(viewModel.postRunPromptState == .completion(outputFolder: output, outputCount: 1), "Success should first show completion prompt")
            try viewModel.acknowledgeSuccess(openOutputFolder: true)
            expect(finder.openedURL == output, "Open Output Folder should call Finder")
            expect(viewModel.postRunPromptState == .trashPrompt, "Trash prompt should follow completion prompt")
            try viewModel.dismissTrashPrompt(shouldTrashOriginal: true)
            expect(trash.trashedURL == input, "Trash action should move original after success prompt")
        } catch {
            failures.append("Success/trash ordering test failed: \(error)")
        }
    }

    mutating private func testTrashPromptAbsentOnFailure() async {
        do {
            let temp = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: temp) }
            let input = temp.appendingPathComponent("recording.mov")
            let output = temp.appendingPathComponent("out", isDirectory: true)
            try Data().write(to: input)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let viewModel = AppViewModel(locator: MockLocator(location: FFmpegLocation(executableURL: URL(fileURLWithPath: "/bin/ffmpeg"), checkedPaths: ["/bin/ffmpeg"])), runner: MockRunner(result: FFmpegResult(exitCode: 2, stdout: "", stderr: "bad things\n")))
            viewModel.inputFile = input
            viewModel.outputFolder = output
            await viewModel.start()
            expect(viewModel.postRunPromptState == .error("ffmpeg exited with code 2. bad things"), "Failure should produce an error prompt")
            expect(viewModel.postRunPromptState != .trashPrompt, "Failure must not show trash prompt")
        } catch {
            failures.append("Failure prompt test failed: \(error)")
        }
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private final class MockLocator: FFmpegLocating {
    let location: FFmpegLocation
    private(set) var receivedOverridePath: String?

    init(location: FFmpegLocation) {
        self.location = location
    }

    func locateFFmpeg(overridePath: String?) -> FFmpegLocation {
        receivedOverridePath = overridePath
        return location
    }
}

private final class MockRunner: FFmpegRunning {
    private let result: FFmpegResult
    private let onRun: () -> Void
    private(set) var receivedCommand: FFmpegCommand?

    init(result: FFmpegResult, onRun: @escaping () -> Void = {}) {
        self.result = result
        self.onRun = onRun
    }

    func run(command: FFmpegCommand, logHandler: @escaping @Sendable (String) -> Void) async throws -> FFmpegResult {
        receivedCommand = command
        onRun()
        logHandler("mock log")
        return result
    }
}

private final class MockFinder: FinderOpening {
    private(set) var openedURL: URL?
    func openFolder(_ url: URL) throws { openedURL = url }
}

private final class MockTrash: TrashHandling {
    private(set) var trashedURL: URL?
    func moveToTrash(_ url: URL) throws { trashedURL = url }
}

var runner = TestRunner()
await runner.run()
