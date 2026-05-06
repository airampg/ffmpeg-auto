import Foundation
import HTTPTypes
import Hummingbird
import NIOCore

struct ZipHandler: Sendable {
    let store: JobStore
    let workdir: URL

    func handle(_ request: Request, context: some RequestContext) async throws -> Response {
        guard let idString = context.parameters.get("id"), let id = UUID(uuidString: idString) else {
            return APIError.jobNotFound.toResponse()
        }
        guard let job = await store.get(id) else {
            return APIError.jobNotFound.toResponse()
        }
        guard job.status == .succeeded, !job.outputs.isEmpty else {
            return APIError.jobNotDownloadable.toResponse()
        }

        let outputDir = workdir.appendingPathComponent("outputs").appendingPathComponent(id.uuidString)
        let data: Data
        do {
            data = try buildZip(in: outputDir, files: job.outputs.map(\.name))
        } catch {
            return APIError.storageError(error.localizedDescription).toResponse()
        }

        var headers = HTTPFields()
        headers[.contentType] = "application/zip"
        headers[.contentDisposition] = "attachment; filename=\"\(id.uuidString).zip\""
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
        )
    }

    private func buildZip(in dir: URL, files: [String]) throws -> Data {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = dir
        process.arguments = ["-j", "-0", "-q", "-"] + files
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errData, encoding: .utf8) ?? "zip exited with code \(process.terminationStatus)"
            throw NSError(domain: "ZipHandler", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
        return data
    }
}
