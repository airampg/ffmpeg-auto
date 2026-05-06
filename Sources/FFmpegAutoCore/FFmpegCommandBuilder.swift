import Foundation

public struct FFmpegCommandBuilder {
    public init() {}

    public func build(from conversion: ValidatedConversion) -> FFmpegCommand {
        var arguments: [String] = []

        // Both -ss and -to go BEFORE -i so they act as input options:
        //   -ss = stop reading the input until position
        //   -to = stop reading the input AT position (absolute input timestamp)
        // Placed after -i, -to becomes an output option meaning "stop writing when
        // the OUTPUT duration reaches X", which combined with -ss before -i causes
        // the end mark to be ignored once the input is exhausted.
        if let start = conversion.trimStartSeconds, start > 0 {
            arguments += ["-ss", Self.formatTimestamp(start)]
        }
        if let end = conversion.trimEndSeconds {
            arguments += ["-to", Self.formatTimestamp(end)]
        }

        arguments += ["-i", conversion.inputFile.path]

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
