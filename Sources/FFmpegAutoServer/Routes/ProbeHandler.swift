import Foundation
import HTTPTypes
import Hummingbird
import NIOCore

struct ProbeHandler: Sendable {
    let configuration: Configuration
    let probeService: ProbeService?
    let workdir: URL

    func probe(_ request: Request, context: some RequestContext) async throws -> Response {
        guard let probeService else {
            return APIError.ffmpegUnavailable.toResponse()
        }
        guard let contentType = request.headers[.contentType] else {
            return APIError.malformedMultipart("missing Content-Type").toResponse()
        }
        guard contentType.lowercased().contains("multipart/form-data") else {
            return APIError.malformedMultipart("expected multipart/form-data").toResponse()
        }

        do {
            let upload = try await MultipartParsing.parse(
                request: request,
                contentType: contentType,
                maxBytes: configuration.maxUploadBytes
            )

            // Write to a short-lived temp file inside workdir so ffprobe can scan it.
            let tempDir = workdir.appendingPathComponent("probe", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempFile = tempDir.appendingPathComponent("\(UUID().uuidString)-\(UploadStore.sanitizeFilename(upload.fileFilename))")
            do {
                try upload.fileBytes.write(to: tempFile, options: .atomic)
            } catch {
                return APIError.storageError("Failed to stage probe file: \(error.localizedDescription)").toResponse()
            }
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let duration = await probeService.probeDuration(of: tempFile)
            let body = ProbeResponse(durationSeconds: duration)
            return try JSONResponse.make(body)
        } catch let api as APIError {
            return api.toResponse()
        } catch {
            return APIError.internalError(error.localizedDescription).toResponse()
        }
    }
}

struct ProbeResponse: Encodable, Sendable {
    let durationSeconds: Double?
}
