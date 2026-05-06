import Foundation
@preconcurrency import FFmpegAutoCore

public struct JobSubmitDTO: Codable, Sendable {
    public var segmentMinutes: Int
    public var audioOnly: Bool?
    public var codec: String
    public var container: String
    public var bitrate: String
    public var sampleRate: Int
    public var channels: Int
    public var filenamePrefix: String?
    public var resetTimestamps: Bool?
    public var collisionPolicy: String?
    public var loudnessNormalizationEnabled: Bool?
    public var extraFFmpegArguments: String?
    public var trimStartSeconds: Double?
    public var trimEndSeconds: Double?

    public func toSettings() throws -> AudioConversionSettings {
        guard let codecValue = AudioCodec(rawValue: codec) else {
            throw AppValidationError.incompatibleCodecContainer(.aac, .m4a)
        }
        guard let containerValue = OutputContainer(rawValue: container) else {
            throw AppValidationError.incompatibleCodecContainer(codecValue, .m4a)
        }
        guard let channelValue = AudioChannelCount(rawValue: channels) else {
            throw AppValidationError.invalidSampleRate(channels)
        }
        let policyValue = OutputCollisionPolicy(rawValue: collisionPolicy ?? "failIfExists") ?? .failIfExists

        return AudioConversionSettings(
            audioOnly: audioOnly ?? true,
            codec: codecValue,
            container: containerValue,
            bitrate: bitrate,
            sampleRate: sampleRate,
            channelCount: channelValue,
            filenamePrefix: filenamePrefix ?? "meeting",
            resetTimestamps: resetTimestamps ?? true,
            collisionPolicy: policyValue,
            loudnessNormalizationEnabled: loudnessNormalizationEnabled ?? false,
            extraFFmpegArgumentsText: extraFFmpegArguments ?? "",
            ffmpegPathOverride: "",
            trimStartSeconds: trimStartSeconds,
            trimEndSeconds: trimEndSeconds
        )
    }
}

public struct JobCreatedResponse: Encodable, Sendable {
    public let jobId: String
    public let status: String

    public init(jobId: UUID, status: JobStatus) {
        self.jobId = jobId.uuidString
        self.status = status.rawValue
    }
}

public struct JobSummaryDTO: Encodable, Sendable {
    public let jobId: String
    public let status: String
    public let createdAt: Date
    public let startedAt: Date?
    public let finishedAt: Date?
    public let inputFilename: String

    public init(_ job: Job) {
        self.jobId = job.id.uuidString
        self.status = job.status.rawValue
        self.createdAt = job.createdAt
        self.startedAt = job.startedAt
        self.finishedAt = job.finishedAt
        self.inputFilename = job.originalFilename
    }
}

public struct JobListResponse: Encodable, Sendable {
    public let jobs: [JobSummaryDTO]
}

public struct JobDetailResponse: Encodable, Sendable {
    public let jobId: String
    public let status: String
    public let createdAt: Date
    public let startedAt: Date?
    public let finishedAt: Date?
    public let inputFilename: String
    public let command: String?
    public let progress: Progress
    public let outputCount: Int?
    public let outputs: [JobOutput]
    public let errorMessage: String?

    public struct Progress: Encodable, Sendable {
        public let percent: Double?
        public let currentTimeSeconds: Double?
        public let totalDurationSeconds: Double?
    }

    public init(_ job: Job) {
        self.jobId = job.id.uuidString
        self.status = job.status.rawValue
        self.createdAt = job.createdAt
        self.startedAt = job.startedAt
        self.finishedAt = job.finishedAt
        self.inputFilename = job.originalFilename
        self.command = job.commandDisplay
        let percent: Double?
        if let total = job.totalDurationSeconds, total > 0, let now = job.currentTimeSeconds {
            percent = min((now / total) * 100, 100)
        } else {
            percent = nil
        }
        self.progress = Progress(
            percent: percent,
            currentTimeSeconds: job.currentTimeSeconds,
            totalDurationSeconds: job.totalDurationSeconds
        )
        self.outputCount = job.status == .succeeded ? job.outputs.count : nil
        self.outputs = job.outputs
        self.errorMessage = job.errorMessage
    }
}
