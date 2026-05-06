import Foundation

public enum ProcessingState: Equatable {
    case idle
    case running
    case success(outputFolder: URL, outputCount: Int?)
    case failure(message: String)
}

public struct FFmpegCommand: Equatable {
    public let executableURL: URL
    public let arguments: [String]

    public init(executableURL: URL, arguments: [String]) {
        self.executableURL = executableURL
        self.arguments = arguments
    }
}

public struct FFmpegResult: Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum AudioCodec: String, CaseIterable, Identifiable, Equatable {
    case aac
    case mp3
    case opus
    case pcmS16LE

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aac: return "AAC"
        case .mp3: return "MP3"
        case .opus: return "Opus"
        case .pcmS16LE: return "PCM 16-bit"
        }
    }

    public var ffmpegName: String {
        switch self {
        case .aac: return "aac"
        case .mp3: return "libmp3lame"
        case .opus: return "libopus"
        case .pcmS16LE: return "pcm_s16le"
        }
    }
}

public enum OutputContainer: String, CaseIterable, Identifiable, Equatable {
    case m4a
    case mp3
    case opus
    case wav

    public var id: String { rawValue }
    public var displayName: String { rawValue.uppercased() }
    public var fileExtension: String { rawValue }
}

public enum AudioChannelCount: Int, CaseIterable, Identifiable, Equatable {
    case mono = 1
    case stereo = 2

    public var id: Int { rawValue }
    public var displayName: String { self == .mono ? "Mono" : "Stereo" }
}

public enum OutputCollisionPolicy: String, CaseIterable, Identifiable, Equatable {
    case failIfExists
    case overwriteMatchingSegments

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .failIfExists: return "Stop if matching files exist"
        case .overwriteMatchingSegments: return "Overwrite matching segment files"
        }
    }
}

public struct AudioConversionSettings: Equatable {
    public var audioOnly: Bool
    public var codec: AudioCodec
    public var container: OutputContainer
    public var bitrate: String
    public var sampleRate: Int
    public var channelCount: AudioChannelCount
    public var filenamePrefix: String
    public var resetTimestamps: Bool
    public var collisionPolicy: OutputCollisionPolicy
    public var loudnessNormalizationEnabled: Bool
    public var extraFFmpegArgumentsText: String
    public var ffmpegPathOverride: String

    public init(
        audioOnly: Bool,
        codec: AudioCodec,
        container: OutputContainer,
        bitrate: String,
        sampleRate: Int,
        channelCount: AudioChannelCount,
        filenamePrefix: String,
        resetTimestamps: Bool,
        collisionPolicy: OutputCollisionPolicy,
        loudnessNormalizationEnabled: Bool,
        extraFFmpegArgumentsText: String,
        ffmpegPathOverride: String
    ) {
        self.audioOnly = audioOnly
        self.codec = codec
        self.container = container
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.filenamePrefix = filenamePrefix
        self.resetTimestamps = resetTimestamps
        self.collisionPolicy = collisionPolicy
        self.loudnessNormalizationEnabled = loudnessNormalizationEnabled
        self.extraFFmpegArgumentsText = extraFFmpegArgumentsText
        self.ffmpegPathOverride = ffmpegPathOverride
    }

    public static let transcriptionDefault = AudioConversionSettings(
        audioOnly: true,
        codec: .aac,
        container: .m4a,
        bitrate: "48k",
        sampleRate: 16000,
        channelCount: .mono,
        filenamePrefix: "meeting",
        resetTimestamps: true,
        collisionPolicy: .failIfExists,
        loudnessNormalizationEnabled: false,
        extraFFmpegArgumentsText: "",
        ffmpegPathOverride: ""
    )
}

public struct FFmpegLocation: Equatable {
    public let executableURL: URL?
    public let checkedPaths: [String]

    public init(executableURL: URL?, checkedPaths: [String]) {
        self.executableURL = executableURL
        self.checkedPaths = checkedPaths
    }
}

public struct ValidationContext: Equatable {
    public let inputFile: URL?
    public let outputFolder: URL?
    public let segmentMinutesText: String
    public let ffmpegLocation: FFmpegLocation
    public let settings: AudioConversionSettings

    public init(inputFile: URL?, outputFolder: URL?, segmentMinutesText: String, ffmpegLocation: FFmpegLocation, settings: AudioConversionSettings = .transcriptionDefault) {
        self.inputFile = inputFile
        self.outputFolder = outputFolder
        self.segmentMinutesText = segmentMinutesText
        self.ffmpegLocation = ffmpegLocation
        self.settings = settings
    }
}

public struct ValidatedConversion: Equatable {
    public let inputFile: URL
    public let outputFolder: URL
    public let segmentMinutes: Int
    public let segmentSeconds: Int
    public let ffmpegExecutableURL: URL
    public let outputPattern: URL
    public let settings: AudioConversionSettings
    public let extraFFmpegArguments: [String]

    public init(inputFile: URL, outputFolder: URL, segmentMinutes: Int, ffmpegExecutableURL: URL, outputPattern: URL, settings: AudioConversionSettings = .transcriptionDefault, extraFFmpegArguments: [String] = []) {
        self.inputFile = inputFile
        self.outputFolder = outputFolder
        self.segmentMinutes = segmentMinutes
        self.segmentSeconds = segmentMinutes * 60
        self.ffmpegExecutableURL = ffmpegExecutableURL
        self.outputPattern = outputPattern
        self.settings = settings
        self.extraFFmpegArguments = extraFFmpegArguments
    }
}

public enum AppValidationError: LocalizedError, Equatable {
    case missingInputFile
    case missingOutputFolder
    case emptySegmentLength
    case nonNumericSegmentLength
    case segmentLengthTooSmall(minimum: Int)
    case segmentLengthTooLarge(maximum: Int)
    case missingFFmpeg(checkedPaths: [String])
    case inputFileMissing(String)
    case inputFileUnreadable(String)
    case outputFolderMissing(String)
    case outputFolderNotWritable(String)
    case existingOutputFiles(String, String)
    case incompatibleCodecContainer(AudioCodec, OutputContainer)
    case invalidBitrate(String)
    case invalidSampleRate(Int)
    case invalidFilenamePrefix
    case invalidExtraFFmpegArguments(String)

    public var errorDescription: String? {
        switch self {
        case .missingInputFile:
            return "Select an input media file before starting."
        case .missingOutputFolder:
            return "Choose an output folder before starting."
        case .emptySegmentLength:
            return "Enter a segment length between 1 and 180 minutes."
        case .nonNumericSegmentLength:
            return "Segment length must be a whole number of minutes."
        case .segmentLengthTooSmall(let minimum):
            return "Segment length must be at least \(minimum) minute."
        case .segmentLengthTooLarge(let maximum):
            return "Segment length must be no more than \(maximum) minutes."
        case .missingFFmpeg(let checkedPaths):
            return "ffmpeg was not found. Checked: \(checkedPaths.joined(separator: ", ")). Install it with `brew install ffmpeg` or set an advanced ffmpeg path override."
        case .inputFileMissing(let path):
            return "The selected input file does not exist: \(path)"
        case .inputFileUnreadable(let path):
            return "The selected input file is not readable: \(path)"
        case .outputFolderMissing(let path):
            return "The selected output folder does not exist: \(path)"
        case .outputFolderNotWritable(let path):
            return "The selected output folder is not writable: \(path)"
        case .existingOutputFiles(let prefix, let fileExtension):
            return "The output folder already contains files matching \(prefix)_###.\(fileExtension). Choose a different folder, remove those files, or change the advanced collision policy."
        case .incompatibleCodecContainer(let codec, let container):
            return "\(codec.displayName) audio is not compatible with the \(container.displayName) container in this app. Choose a matching codec/container pair."
        case .invalidBitrate(let value):
            return "Audio bitrate must look like 48k, 64k, 96k, or 128k. Current value: \(value)"
        case .invalidSampleRate(let value):
            return "Sample rate must be one of 8000, 12000, 16000, 22050, 24000, 32000, 44100, or 48000 Hz. Current value: \(value)"
        case .invalidFilenamePrefix:
            return "Filename prefix cannot be empty after sanitising. Use a simple prefix such as meeting."
        case .invalidExtraFFmpegArguments(let reason):
            return "Custom FFmpeg arguments are invalid: \(reason)"
        }
    }
}

public enum PostRunPromptState: Equatable {
    case none
    case completion(outputFolder: URL, outputCount: Int?)
    case trashPrompt
    case error(String)
}

public enum AppActionError: LocalizedError, Equatable {
    case openFolderFailed(String)
    case trashFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFolderFailed(let path):
            return "Could not open the output folder in Finder: \(path)"
        case .trashFailed(let message):
            return "Could not move the original file to the Trash: \(message)"
        }
    }
}
