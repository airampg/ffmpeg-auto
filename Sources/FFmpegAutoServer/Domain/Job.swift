import Foundation
@preconcurrency import FFmpegAutoCore

public enum JobStatus: String, Codable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
}

public struct JobOutput: Codable, Sendable, Equatable {
    public let name: String
    public let sizeBytes: Int64

    public init(name: String, sizeBytes: Int64) {
        self.name = name
        self.sizeBytes = sizeBytes
    }
}

public struct Job: Sendable {
    public let id: UUID
    public let originalFilename: String
    public let inputFileURL: URL
    public let outputFolderURL: URL
    public let settings: AudioConversionSettings
    public let segmentMinutes: Int
    public let createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var status: JobStatus
    public var commandDisplay: String?
    public var totalDurationSeconds: Double?
    public var currentTimeSeconds: Double?
    public var errorMessage: String?
    public var outputs: [JobOutput]
    public var logBuffer: RingLog
    public var ffmpegProcessIdentifier: Int32?

    public init(
        id: UUID,
        originalFilename: String,
        inputFileURL: URL,
        outputFolderURL: URL,
        settings: AudioConversionSettings,
        segmentMinutes: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.originalFilename = originalFilename
        self.inputFileURL = inputFileURL
        self.outputFolderURL = outputFolderURL
        self.settings = settings
        self.segmentMinutes = segmentMinutes
        self.createdAt = createdAt
        self.status = .queued
        self.outputs = []
        self.logBuffer = RingLog()
    }
}
