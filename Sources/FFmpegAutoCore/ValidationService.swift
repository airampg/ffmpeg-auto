import Foundation

public struct ValidationService {
    public let minimumMinutes: Int
    public let maximumMinutes: Int
    private let namingService: FileNamingService
    private let fileManager: FileManager

    public init(minimumMinutes: Int = 1, maximumMinutes: Int = 180, namingService: FileNamingService = FileNamingService(), fileManager: FileManager = .default) {
        self.minimumMinutes = minimumMinutes
        self.maximumMinutes = maximumMinutes
        self.namingService = namingService
        self.fileManager = fileManager
    }

    public func validate(_ context: ValidationContext) throws -> ValidatedConversion {
        guard let inputFile = context.inputFile else { throw AppValidationError.missingInputFile }
        guard let outputFolder = context.outputFolder else { throw AppValidationError.missingOutputFolder }
        let segmentMinutes = try validateSegmentMinutes(context.segmentMinutesText)
        let settings = context.settings
        try validateAudioSettings(settings)
        let extraArguments = try parseExtraFFmpegArguments(settings.extraFFmpegArgumentsText)
        guard let ffmpegExecutableURL = context.ffmpegLocation.executableURL else {
            throw AppValidationError.missingFFmpeg(checkedPaths: context.ffmpegLocation.checkedPaths)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputFile.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw AppValidationError.inputFileMissing(inputFile.path)
        }
        guard fileManager.isReadableFile(atPath: inputFile.path) else {
            throw AppValidationError.inputFileUnreadable(inputFile.path)
        }

        var outputIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: outputFolder.path, isDirectory: &outputIsDirectory), outputIsDirectory.boolValue else {
            throw AppValidationError.outputFolderMissing(outputFolder.path)
        }

        guard fileManager.isWritableFile(atPath: outputFolder.path) else {
            throw AppValidationError.outputFolderNotWritable(outputFolder.path)
        }

        if settings.collisionPolicy == .failIfExists,
           namingService.hasExistingSegmentOutputs(inputFile: inputFile, outputFolder: outputFolder, settings: settings, fileManager: fileManager) {
            throw AppValidationError.existingOutputFiles(namingService.outputPrefix(for: inputFile, filenamePrefix: settings.filenamePrefix), settings.container.fileExtension)
        }

        return ValidatedConversion(
            inputFile: inputFile,
            outputFolder: outputFolder,
            segmentMinutes: segmentMinutes,
            ffmpegExecutableURL: ffmpegExecutableURL,
            outputPattern: namingService.outputPattern(inputFile: inputFile, outputFolder: outputFolder, settings: settings),
            settings: settings,
            extraFFmpegArguments: extraArguments
        )
    }

    public func validateSegmentMinutes(_ text: String) throws -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppValidationError.emptySegmentLength }
        guard let value = Int(trimmed) else { throw AppValidationError.nonNumericSegmentLength }
        guard value >= minimumMinutes else { throw AppValidationError.segmentLengthTooSmall(minimum: minimumMinutes) }
        guard value <= maximumMinutes else { throw AppValidationError.segmentLengthTooLarge(maximum: maximumMinutes) }
        return value
    }

    public func validateAudioSettings(_ settings: AudioConversionSettings) throws {
        guard isCompatible(codec: settings.codec, container: settings.container) else {
            throw AppValidationError.incompatibleCodecContainer(settings.codec, settings.container)
        }
        if settings.codec != .pcmS16LE {
            let digits = settings.bitrate.dropLast()
            guard settings.bitrate.hasSuffix("k"), digits.count >= 2, digits.count <= 4, digits.allSatisfy(\.isNumber) else {
                throw AppValidationError.invalidBitrate(settings.bitrate)
            }
        }
        let allowedSampleRates: Set<Int> = [8000, 12000, 16000, 22050, 24000, 32000, 44100, 48000]
        guard allowedSampleRates.contains(settings.sampleRate) else {
            throw AppValidationError.invalidSampleRate(settings.sampleRate)
        }
        guard !namingService.sanitizedPrefix(settings.filenamePrefix).isEmpty else {
            throw AppValidationError.invalidFilenamePrefix
        }
    }

    public func isCompatible(codec: AudioCodec, container: OutputContainer) -> Bool {
        switch (codec, container) {
        case (.aac, .m4a), (.mp3, .mp3), (.opus, .opus), (.pcmS16LE, .wav):
            return true
        default:
            return false
        }
    }

    public func parseExtraFFmpegArguments(_ text: String) throws -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var result: [String] = []
        var current = ""
        var isInQuotes = false
        var isEscaping = false

        for character in trimmed {
            if isEscaping {
                current.append(character)
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else if character == "\"" {
                isInQuotes.toggle()
            } else if character.isWhitespace && !isInQuotes {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        guard !isEscaping else { throw AppValidationError.invalidExtraFFmpegArguments("Trailing escape character.") }
        guard !isInQuotes else { throw AppValidationError.invalidExtraFFmpegArguments("Unclosed quote.") }
        if !current.isEmpty { result.append(current) }
        guard result.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw AppValidationError.invalidExtraFFmpegArguments("Empty argument.")
        }
        return result
    }
}
