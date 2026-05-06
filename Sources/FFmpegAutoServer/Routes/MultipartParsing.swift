import Foundation
import HTTPTypes
import Hummingbird
import MultipartKit
import NIOCore

public struct MultipartUpload: Sendable {
    public let settingsJSON: Data
    public let fileFilename: String
    public let fileBytes: Data
}

public enum MultipartParsing {
    public static func parse(
        request: Request,
        contentType: String,
        maxBytes: Int64
    ) async throws -> MultipartUpload {
        guard let boundary = extractBoundary(from: contentType) else {
            throw APIError.malformedMultipart("missing boundary in Content-Type")
        }

        let buffer = try await collectBody(request: request, maxBytes: maxBytes)

        var parts: [(name: String?, filename: String?, body: Data)] = []
        var currentHeaders: [(String, String)] = []
        var currentBody = ByteBufferAllocator().buffer(capacity: 1024)

        let parser = MultipartParser(boundary: boundary)
        parser.onHeader = { field, value in
            currentHeaders.append((field, value))
        }
        parser.onBody = { buffer in
            var b = buffer
            currentBody.writeBuffer(&b)
        }
        parser.onPartComplete = {
            let disposition = currentHeaders.first { $0.0.lowercased() == "content-disposition" }?.1 ?? ""
            let name = extractParameter(from: disposition, name: "name")
            let filename = extractParameter(from: disposition, name: "filename")
            let raw = currentBody.getBytes(at: currentBody.readerIndex, length: currentBody.readableBytes) ?? []
            let bytes = Data(raw)
            parts.append((name: name, filename: filename, body: bytes))
            currentHeaders = []
            currentBody = ByteBufferAllocator().buffer(capacity: 1024)
        }

        do {
            try parser.execute(buffer)
        } catch {
            throw APIError.malformedMultipart(String(describing: error))
        }

        guard let settingsPart = parts.first(where: { $0.name == "settings" }) else {
            throw APIError.malformedMultipart("missing 'settings' part")
        }
        guard let filePart = parts.first(where: { $0.name == "file" }), let filename = filePart.filename else {
            throw APIError.malformedMultipart("missing 'file' part with filename")
        }

        if Int64(filePart.body.count) > maxBytes {
            throw APIError.uploadTooLarge(limit: maxBytes)
        }

        return MultipartUpload(
            settingsJSON: settingsPart.body,
            fileFilename: filename,
            fileBytes: filePart.body
        )
    }

    private static func collectBody(request: Request, maxBytes: Int64) async throws -> ByteBuffer {
        let upTo = Int(min(maxBytes, Int64(Int.max - 1)))
        do {
            return try await request.body.collect(upTo: upTo)
        } catch {
            throw APIError.uploadTooLarge(limit: maxBytes)
        }
    }

    static func extractBoundary(from contentType: String) -> String? {
        let parts = contentType.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts {
            if part.lowercased().hasPrefix("boundary=") {
                var boundary = String(part.dropFirst("boundary=".count))
                if boundary.hasPrefix("\"") && boundary.hasSuffix("\"") {
                    boundary = String(boundary.dropFirst().dropLast())
                }
                return boundary.isEmpty ? nil : boundary
            }
        }
        return nil
    }

    static func extractParameter(from header: String, name: String) -> String? {
        let lowered = header.lowercased()
        let needle = "\(name.lowercased())="
        guard let range = lowered.range(of: needle) else { return nil }
        let startIndex = header.index(header.startIndex, offsetBy: lowered.distance(from: lowered.startIndex, to: range.upperBound))
        let remainder = header[startIndex...]
        if remainder.hasPrefix("\"") {
            let afterQuote = remainder.dropFirst()
            if let endQuote = afterQuote.firstIndex(of: "\"") {
                return String(afterQuote[afterQuote.startIndex..<endQuote])
            }
        }
        if let semicolon = remainder.firstIndex(of: ";") {
            return String(remainder[remainder.startIndex..<semicolon]).trimmingCharacters(in: .whitespaces)
        }
        return String(remainder).trimmingCharacters(in: .whitespaces)
    }
}
