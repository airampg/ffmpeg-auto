import Foundation
import FFmpegAutoCore

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var inputFile: URL?
    @Published public var outputFolder: URL?
    @Published public var segmentMinutesDraft: String
    @Published public private(set) var segmentMinutes: Int
    @Published public private(set) var segmentDurationMessage = "Default: 15 minutes. Valid range: 1 to 180."
    @Published public var settings: AudioConversionSettings
    @Published public private(set) var advancedValidationMessage = "Advanced defaults are transcription-ready: AAC, M4A, mono, 16 kHz, 48k."
    @Published public private(set) var state: ProcessingState = .idle
    @Published public private(set) var postRunPromptState: PostRunPromptState = .none
    @Published public private(set) var statusText = "Select an input file and output folder."
    @Published public private(set) var logs = ""

    public var isProcessing: Bool {
        if case .running = state { return true }
        return false
    }

    private let locator: FFmpegLocating
    private let validator: ValidationService
    private let commandBuilder: FFmpegCommandBuilder
    private let runner: FFmpegRunning
    private let finder: FinderOpening
    private let trash: TrashHandling
    private let namingService: FileNamingService
    private var lastSuccessfulInputFile: URL?

    public init(
        segmentMinutesText: String = "15",
        settings: AudioConversionSettings = .transcriptionDefault,
        locator: FFmpegLocating = FFmpegLocator(),
        validator: ValidationService = ValidationService(),
        commandBuilder: FFmpegCommandBuilder = FFmpegCommandBuilder(),
        runner: FFmpegRunning = FFmpegRunner(),
        finder: FinderOpening = FinderService(),
        trash: TrashHandling = TrashService(),
        namingService: FileNamingService = FileNamingService()
    ) {
        self.segmentMinutesDraft = segmentMinutesText
        self.segmentMinutes = Int(segmentMinutesText) ?? 15
        self.settings = settings
        self.locator = locator
        self.validator = validator
        self.commandBuilder = commandBuilder
        self.runner = runner
        self.finder = finder
        self.trash = trash
        self.namingService = namingService
    }

    public var canStart: Bool {
        !isProcessing
    }

    public var settingsSummary: String {
        "\(settings.codec.displayName) · \(settings.container.displayName) · \(settings.sampleRate) Hz · \(settings.channelCount.displayName) · \(settings.bitrate)"
    }

    public func segmentMinutesDraftChanged(_ newValue: String) {
        segmentMinutesDraft = newValue
        do {
            let value = try validator.validateSegmentMinutes(newValue)
            segmentMinutes = value
            segmentDurationMessage = "Will create chunks of \(value) minute\(value == 1 ? "" : "s") (\(value * 60) seconds)."
        } catch {
            segmentDurationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func commitSegmentMinutesDraft() {
        do {
            let value = try validator.validateSegmentMinutes(segmentMinutesDraft)
            segmentMinutes = value
            segmentMinutesDraft = String(value)
            segmentDurationMessage = "Will create chunks of \(value) minute\(value == 1 ? "" : "s") (\(value * 60) seconds)."
        } catch {
            segmentDurationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func advancedSettingsChanged() {
        do {
            try validator.validateAudioSettings(settings)
            _ = try validator.parseExtraFFmpegArguments(settings.extraFFmpegArgumentsText)
            advancedValidationMessage = "Advanced settings look valid. Output will use \(settings.container.displayName) chunks with \(settings.codec.displayName) audio."
        } catch {
            advancedValidationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func setSegmentMinutes(_ value: Int) {
        let bounded = min(max(value, validator.minimumMinutes), validator.maximumMinutes)
        segmentMinutes = bounded
        segmentMinutesDraft = String(bounded)
        segmentDurationMessage = "Will create chunks of \(bounded) minute\(bounded == 1 ? "" : "s") (\(bounded * 60) seconds)."
    }

    public func start() async {
        guard !isProcessing else { return }
        commitSegmentMinutesDraft()
        logs = ""
        state = .running
        postRunPromptState = .none
        statusText = "Validating inputs..."

        do {
            let conversion = try validator.validate(ValidationContext(
                inputFile: inputFile,
                outputFolder: outputFolder,
                segmentMinutesText: segmentMinutesDraft,
                ffmpegLocation: locator.locateFFmpeg(overridePath: settings.ffmpegPathOverride),
                settings: settings
            ))
            let command = commandBuilder.build(from: conversion)
            appendLog("Running: \(commandBuilder.displayTemplate(for: conversion))\n")
            statusText = "Processing audio chunks..."

            let result = try await runner.run(command: command) { [weak self] text in
                Task { @MainActor in self?.appendLog(text) }
            }

            if result.exitCode == 0 {
                let count = namingService.countGeneratedOutputs(inputFile: conversion.inputFile, outputFolder: conversion.outputFolder, settings: conversion.settings)
                lastSuccessfulInputFile = conversion.inputFile
                state = .success(outputFolder: conversion.outputFolder, outputCount: count)
                postRunPromptState = .completion(outputFolder: conversion.outputFolder, outputCount: count)
                statusText = "Processing complete."
            } else {
                let stderr = Self.lastMeaningfulLine(from: result.stderr)
                let message = "ffmpeg exited with code \(result.exitCode). \(stderr.isEmpty ? "No error details were reported." : stderr)"
                state = .failure(message: message)
                postRunPromptState = .error(message)
                statusText = "Processing failed."
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .failure(message: message)
            postRunPromptState = .error(message)
            statusText = "Processing failed."
        }
    }

    public func acknowledgeSuccess(openOutputFolder: Bool) throws {
        guard case .completion = postRunPromptState else { return }
        if openOutputFolder {
            try openOutputFolderFromSuccess()
        }
        postRunPromptState = .trashPrompt
    }

    public func dismissTrashPrompt(shouldTrashOriginal: Bool) throws {
        guard postRunPromptState == .trashPrompt else { return }
        if shouldTrashOriginal {
            try moveOriginalToTrashAfterSuccess()
        }
        postRunPromptState = .none
    }

    public func openOutputFolderFromSuccess() throws {
        guard case .success(let outputFolder, _) = state else { return }
        try finder.openFolder(outputFolder)
    }

    public func moveOriginalToTrashAfterSuccess() throws {
        guard case .success = state, let inputFile = lastSuccessfulInputFile else { return }
        try trash.moveToTrash(inputFile)
    }

    public func resetAfterFailureAcknowledged() {
        if case .failure = state {
            state = .idle
            postRunPromptState = .none
            statusText = "Fix the issue and try again."
        }
    }

    private func appendLog(_ text: String) {
        logs += text
        if logs.count > 80_000 {
            logs.removeFirst(logs.count - 80_000)
        }
    }

    private static func lastMeaningfulLine(from stderr: String) -> String {
        stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty } ?? ""
    }
}
