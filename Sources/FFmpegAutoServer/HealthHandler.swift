import Foundation
import Hummingbird

struct HealthResponse: Encodable {
    let status: String
    let ffmpegVersion: String
}

struct HealthHandler: Sendable {
    let probe: FFmpegProbe

    func handle(_ request: Request, context: some RequestContext) async throws -> Response {
        let version = await probe.version()
        let body = HealthResponse(
            status: version == "unavailable" ? "degraded" : "ok",
            ffmpegVersion: version
        )
        return try JSONResponse.make(body)
    }
}
