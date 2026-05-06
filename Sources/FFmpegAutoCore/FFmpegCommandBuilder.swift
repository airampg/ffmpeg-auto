import Foundation

public struct FFmpegCommandBuilder {
    public init() {}

    public func build(from conversion: ValidatedConversion) -> FFmpegCommand {
        var arguments: [String] = []

        // -ss before -i = input-seek (fast). With ffmpeg >= 4.0 this is also accurate
        // to the sub-second, so we don't need -accurate_seek.
        if let start = conversion.trimStartSeconds, start > 0 {
            arguments += ["-ss", Self.formatTimestamp(start)]
        }

        arguments += ["-i", conversion.inputFile.path]

        // -to after -i is interpreted as an absolute timestamp on the input when used
        // together with -ss before -i, which is the behaviour we want.
        if let end = conversion.trimEndSeconds {
            arguments += ["-to", Self.formatTimestamp(end)]
        }

        let settings = conversion.settings

        if settings.collisionPolicy == .overwriteMatchingSegments {
            arguments.append("-y")
        }

        if settings.audioOnly {
            arguments.append("-vn")
        }

        arguments += [
            "-ac", String(settings.channelCount.rawValue),
            "-ar", String(settings.sampleRate),
            "-c:a", settings.codec.ffmpegName
        ]

        if settings.codec != .pcmS16LE {
            arguments += ["-b:a", settings.bitrate]
        }

        if settings.loudnessNormalizationEnabled {
            arguments += ["-af", "loudnorm=I=-16:TP=-1.5:LRA=11"]
        }

        arguments += conversion.extraFFmpegArguments
        arguments += [
            "-f", "segment",
            "-segment_time", String(conversion.segmentSeconds)
        ]

        if settings.resetTimestamps {
            arguments += ["-reset_timestamps", "1"]
        }

        arguments.append(conversion.outputPattern.path)

        return FFmpegCommand(
            executableURL: conversion.ffmpegExecutableURL,
            arguments: arguments
        )
    }

    public func displayTemplate(for conversion: ValidatedConversion) -> String {
        ([conversion.ffmpegExecutableURL.path] + build(from: conversion).arguments)
            .map(quoteForDisplay)
            .joined(separator: " ")
    }

    private func quoteForDisplay(_ value: String) -> String {
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil && !value.contains("\"") {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    /// Formats a seconds value with millisecond precision in the form `12.345`.
    /// ffmpeg accepts both `HH:MM:SS.mmm` and decimal-seconds notation; the latter is
    /// shorter and avoids ambiguity when the value is interpreted by display code.
    public static func formatTimestamp(_ seconds: Double) -> String {
        String(format: "%.3f", seconds)
    }
}
