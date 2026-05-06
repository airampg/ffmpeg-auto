import Foundation
import Hummingbird
import FFmpegAutoCore

struct CapabilitiesResponse: Encodable {
    struct CodecOption: Encodable {
        let id: String
        let displayName: String
        let ffmpegName: String
        let compatibleContainers: [String]
        let bitrateApplicable: Bool
    }
    struct ContainerOption: Encodable {
        let id: String
        let displayName: String
        let fileExtension: String
    }
    struct SegmentRange: Encodable {
        let min: Int
        let max: Int
    }

    let codecs: [CodecOption]
    let containers: [ContainerOption]
    let sampleRates: [Int]
    let channelCounts: [Int]
    let segmentMinutes: SegmentRange
    let collisionPolicies: [String]
    let bitratePattern: String
    let defaultSettings: DefaultSettings

    struct DefaultSettings: Encodable {
        let codec: String
        let container: String
        let bitrate: String
        let sampleRate: Int
        let channels: Int
        let segmentMinutes: Int
        let filenamePrefix: String
        let resetTimestamps: Bool
        let loudnessNormalizationEnabled: Bool
    }
}

struct CapabilitiesHandler: Sendable {
    let validator: ValidationService

    func handle(_ request: Request, context: some RequestContext) async throws -> Response {
        let codecs = AudioCodec.allCases.map { codec in
            let compatible = OutputContainer.allCases.filter { validator.isCompatible(codec: codec, container: $0) }
            return CapabilitiesResponse.CodecOption(
                id: codec.rawValue,
                displayName: codec.displayName,
                ffmpegName: codec.ffmpegName,
                compatibleContainers: compatible.map(\.rawValue),
                bitrateApplicable: codec != .pcmS16LE
            )
        }
        let containers = OutputContainer.allCases.map {
            CapabilitiesResponse.ContainerOption(
                id: $0.rawValue,
                displayName: $0.displayName,
                fileExtension: $0.fileExtension
            )
        }
        let defaults = AudioConversionSettings.transcriptionDefault
        let body = CapabilitiesResponse(
            codecs: codecs,
            containers: containers,
            sampleRates: [8000, 12000, 16000, 22050, 24000, 32000, 44100, 48000],
            channelCounts: AudioChannelCount.allCases.map(\.rawValue),
            segmentMinutes: .init(min: validator.minimumMinutes, max: validator.maximumMinutes),
            collisionPolicies: OutputCollisionPolicy.allCases.map(\.rawValue),
            bitratePattern: "^[0-9]{2,4}k$",
            defaultSettings: .init(
                codec: defaults.codec.rawValue,
                container: defaults.container.rawValue,
                bitrate: defaults.bitrate,
                sampleRate: defaults.sampleRate,
                channels: defaults.channelCount.rawValue,
                segmentMinutes: 15,
                filenamePrefix: defaults.filenamePrefix,
                resetTimestamps: defaults.resetTimestamps,
                loudnessNormalizationEnabled: defaults.loudnessNormalizationEnabled
            )
        )
        return try JSONResponse.make(body)
    }
}
