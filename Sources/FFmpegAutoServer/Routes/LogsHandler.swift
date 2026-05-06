import Foundation
import HTTPTypes
import Hummingbird
import NIOCore

struct LogsHandler: Sendable {
    let store: JobStore
    let orchestrator: JobOrchestrator

    func handle(_ request: Request, context: some RequestContext) async throws -> Response {
        guard let idString = context.parameters.get("id"), let id = UUID(uuidString: idString) else {
            return APIError.jobNotFound.toResponse()
        }
        guard let snapshot = await orchestrator.snapshot(id) else {
            return APIError.jobNotFound.toResponse()
        }

        let liveSubscription: (subID: UUID, stream: AsyncStream<JobEvent>)?
        if snapshot.status.isTerminal {
            liveSubscription = nil
        } else {
            liveSubscription = await orchestrator.subscribe(id)
        }

        let body = ResponseBody { writer in
            // 1. Replay accumulated log buffer.
            if !snapshot.replay.isEmpty {
                let chunk = SSE.encodeLog(snapshot.replay)
                try await writer.write(chunk)
            }

            // 2. Initial status snapshot.
            let statusChunk = try SSE.encodeStatus(snapshot.status)
            try await writer.write(statusChunk)

            // 3. Replay last known progress if any.
            if let current = snapshot.currentTimeSeconds {
                let percent: Double?
                if let total = snapshot.totalDurationSeconds, total > 0 {
                    percent = min((current / total) * 100, 100)
                } else {
                    percent = nil
                }
                let progressChunk = try SSE.encodeProgress(
                    percent: percent,
                    currentTimeSeconds: current,
                    totalDurationSeconds: snapshot.totalDurationSeconds
                )
                try await writer.write(progressChunk)
            }

            if let liveSubscription {
                for await event in liveSubscription.stream {
                    if Task.isCancelled { break }
                    let chunk: ByteBuffer
                    switch event {
                    case .log(let text):
                        chunk = SSE.encodeLog(text)
                    case .progress(let percent, let current, let total):
                        chunk = try SSE.encodeProgress(
                            percent: percent,
                            currentTimeSeconds: current,
                            totalDurationSeconds: total
                        )
                    case .status(let status):
                        chunk = try SSE.encodeStatus(status)
                    case .end:
                        chunk = SSE.encodeRaw(event: "end", data: "{}")
                    }
                    try await writer.write(chunk)
                    if case .end = event { break }
                }
                await orchestrator.unsubscribe(id, liveSubscription.subID)
            } else {
                // Job already terminal — emit end immediately.
                try await writer.write(SSE.encodeRaw(event: "end", data: "{}"))
            }

            try await writer.finish(nil)
        }

        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache, no-transform"
        if let connectionField = HTTPField.Name("connection") {
            headers[connectionField] = "keep-alive"
        }
        if let bufferingField = HTTPField.Name("x-accel-buffering") {
            headers[bufferingField] = "no"
        }

        return Response(status: .ok, headers: headers, body: body)
    }
}

enum SSE {
    static func encodeRaw(event: String, data: String) -> ByteBuffer {
        let body = "event: \(event)\ndata: \(data)\n\n"
        return ByteBuffer(string: body)
    }

    static func encodeLog(_ line: String) -> ByteBuffer {
        let escaped = line
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return encodeRaw(event: "log", data: "{\"line\":\"\(escaped)\"}")
    }

    static func encodeStatus(_ status: JobStatus) throws -> ByteBuffer {
        let payload = ["status": status.rawValue]
        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return encodeRaw(event: "status", data: json)
    }

    struct ProgressPayload: Encodable {
        let percent: Double?
        let currentTimeSeconds: Double?
        let totalDurationSeconds: Double?
    }

    static func encodeProgress(
        percent: Double?,
        currentTimeSeconds: Double?,
        totalDurationSeconds: Double?
    ) throws -> ByteBuffer {
        let payload = ProgressPayload(
            percent: percent,
            currentTimeSeconds: currentTimeSeconds,
            totalDurationSeconds: totalDurationSeconds
        )
        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return encodeRaw(event: "progress", data: json)
    }
}
