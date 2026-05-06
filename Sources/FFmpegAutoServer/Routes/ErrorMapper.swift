import Foundation
import HTTPTypes
import Hummingbird
@preconcurrency import FFmpegAutoCore

public enum APIError: Error, Sendable {
    case validation(AppValidationError)
    case uploadTooLarge(limit: Int64)
    case malformedMultipart(String)
    case malformedSettingsJSON(String)
    case jobNotFound
    case jobQueueFull
    case jobNotDownloadable
    case storageError(String)
    case ffmpegUnavailable
    case internalError(String)

    var status: HTTPResponse.Status {
        switch self {
        case .validation(let err):
            switch err {
            case .missingFFmpeg, .inputFileMissing, .inputFileUnreadable,
                 .outputFolderMissing, .outputFolderNotWritable:
                return .internalServerError
            default:
                return .badRequest
            }
        case .uploadTooLarge: return .contentTooLarge
        case .malformedMultipart, .malformedSettingsJSON: return .badRequest
        case .jobNotFound: return .notFound
        case .jobQueueFull: return .serviceUnavailable
        case .jobNotDownloadable: return .conflict
        case .storageError, .ffmpegUnavailable, .internalError: return .internalServerError
        }
    }

    var code: String {
        switch self {
        case .validation(let err): return Self.code(for: err)
        case .uploadTooLarge: return "UPLOAD_TOO_LARGE"
        case .malformedMultipart: return "INVALID_MULTIPART"
        case .malformedSettingsJSON: return "INVALID_SETTINGS_JSON"
        case .jobNotFound: return "JOB_NOT_FOUND"
        case .jobQueueFull: return "JOB_QUEUE_FULL"
        case .jobNotDownloadable: return "JOB_NOT_DOWNLOADABLE"
        case .storageError: return "STORAGE_ERROR"
        case .ffmpegUnavailable: return "FFMPEG_NOT_AVAILABLE"
        case .internalError: return "INTERNAL_ERROR"
        }
    }

    var message: String {
        switch self {
        case .validation(let err):
            return err.errorDescription ?? "Validation error"
        case .uploadTooLarge(let limit):
            return "Upload exceeds limit of \(limit) bytes."
        case .malformedMultipart(let reason):
            return "Malformed multipart request: \(reason)"
        case .malformedSettingsJSON(let reason):
            return "Malformed settings JSON: \(reason)"
        case .jobNotFound: return "Job not found."
        case .jobQueueFull: return "Job queue is full. Try again later."
        case .jobNotDownloadable: return "Job has not finished successfully yet."
        case .storageError(let reason): return "Storage error: \(reason)"
        case .ffmpegUnavailable: return "ffmpeg is not available in this server image."
        case .internalError(let reason): return "Internal error: \(reason)"
        }
    }

    private static func code(for err: AppValidationError) -> String {
        switch err {
        case .missingInputFile: return "MISSING_INPUT"
        case .missingOutputFolder: return "MISSING_OUTPUT"
        case .emptySegmentLength, .nonNumericSegmentLength: return "INVALID_SEGMENT"
        case .segmentLengthTooSmall, .segmentLengthTooLarge: return "INVALID_SEGMENT_RANGE"
        case .missingFFmpeg: return "FFMPEG_NOT_AVAILABLE"
        case .inputFileMissing, .inputFileUnreadable: return "STORAGE_ERROR"
        case .outputFolderMissing, .outputFolderNotWritable: return "STORAGE_ERROR"
        case .existingOutputFiles: return "OUTPUT_COLLISION"
        case .incompatibleCodecContainer: return "INCOMPATIBLE_CODEC"
        case .invalidBitrate: return "INVALID_BITRATE"
        case .invalidSampleRate: return "INVALID_SAMPLE_RATE"
        case .invalidFilenamePrefix: return "INVALID_PREFIX"
        case .invalidExtraFFmpegArguments: return "INVALID_EXTRAS"
        case .trimStartNegative, .trimEndNotAfterStart, .trimRangeTooShort: return "INVALID_TRIM"
        case .trimEndBeyondDuration: return "TRIM_BEYOND_DURATION"
        }
    }
}

extension APIError {
    func toResponse() -> Response {
        JSONResponse.error(code: code, message: message, status: status)
    }
}
