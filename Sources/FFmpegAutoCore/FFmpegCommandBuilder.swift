import Foundation

public struct FFmpegCommandBuilder {
    public init() {}

    public func build(from conversion: ValidatedConversion) -> FFmpegCommand {
        var arguments = ["-i", conversion.inputFile.path]
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
}
