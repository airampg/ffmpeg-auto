import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
@preconcurrency import FFmpegAutoCore

struct JobsHandler: Sendable {
    let configuration: Configuration
    let orchestrator: JobOrchestrator
    let store: JobStore
    let uploadStore: UploadStore
    let validator: ValidationService

    func create(_ request: Request, context: some RequestContext) async throws -> Response {
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
            let dto: JobSubmitDTO
            do {
                dto = try JSONDecoder().decode(JobSubmitDTO.self, from: upload.settingsJSON)
            } catch {
                throw APIError.malformedSettingsJSON(error.localizedDescription)
            }
            let settings: AudioConversionSettings
            do {
                settings = try dto.toSettings()
            } catch let validation as AppValidationError {
                throw APIError.validation(validation)
            }

            do {
                _ = try validator.validateSegmentMinutes(String(dto.segmentMinutes))
                try validator.validateAudioSettings(settings)
                _ = try validator.parseExtraFFmpegArguments(settings.extraFFmpegArgumentsText)
            } catch let validation as AppValidationError {
                throw APIError.validation(validation)
            }

            let id = try await orchestrator.createJob(
                originalFilename: upload.fileFilename,
                fileBytes: upload.fileBytes,
                settings: settings,
                segmentMinutes: dto.segmentMinutes
            )
            let body = JobCreatedResponse(jobId: id, status: .queued)
            return try JSONResponse.make(body, status: .created)
        } catch let api as APIError {
            return api.toResponse()
        } catch let validation as AppValidationError {
            return APIError.validation(validation).toResponse()
        } catch {
            return APIError.internalError(error.localizedDescription).toResponse()
        }
    }

    func list(_ request: Request, context: some RequestContext) async throws -> Response {
        let jobs = await store.list(limit: 50)
        let body = JobListResponse(jobs: jobs.map(JobSummaryDTO.init))
        return try JSONResponse.make(body)
    }

    func detail(_ request: Request, context: some RequestContext) async throws -> Response {
        guard let idString = context.parameters.get("id"), let id = UUID(uuidString: idString) else {
            return APIError.jobNotFound.toResponse()
        }
        guard let job = await store.get(id) else {
            return APIError.jobNotFound.toResponse()
        }
        return try JSONResponse.make(JobDetailResponse(job))
    }

    func delete(_ request: Request, context: some RequestContext) async throws -> Response {
        guard let idString = context.parameters.get("id"), let id = UUID(uuidString: idString) else {
            return APIError.jobNotFound.toResponse()
        }
        do {
            try await orchestrator.deleteFinishedJob(id)
        } catch let api as APIError {
            return api.toResponse()
        } catch {
            return APIError.internalError(error.localizedDescription).toResponse()
        }
        return Response(status: .noContent)
    }

    func downloadOutput(_ request: Request, context: some RequestContext) async throws -> Response {
        guard let idString = context.parameters.get("id"), let id = UUID(uuidString: idString) else {
            return APIError.jobNotFound.toResponse()
        }
        guard let name = context.parameters.get("name") else {
            return APIError.jobNotFound.toResponse()
        }
        guard let job = await store.get(id) else {
            return APIError.jobNotFound.toResponse()
        }
        guard job.status == .succeeded else {
            return APIError.jobNotDownloadable.toResponse()
        }
        guard let url = await uploadStore.outputFileURL(id, name: name) else {
            return APIError.jobNotFound.toResponse()
        }
        do {
            let data = try Data(contentsOf: url)
            var headers = HTTPFields()
            headers[.contentType] = contentType(for: url)
            headers[.contentDisposition] = "attachment; filename=\"\(name)\""
            return Response(
                status: .ok,
                headers: headers,
                body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
            )
        } catch {
            return APIError.storageError(error.localizedDescription).toResponse()
        }
    }

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "opus": return "audio/ogg"
        case "wav": return "audio/wav"
        default: return "application/octet-stream"
        }
    }
}
