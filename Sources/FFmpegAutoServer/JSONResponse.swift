import Foundation
import HTTPTypes
import Hummingbird
import NIOCore

enum JSONResponse {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static func make<T: Encodable>(_ value: T, status: HTTPResponse.Status = .ok) throws -> Response {
        let data = try encoder.encode(value)
        var headers = HTTPFields()
        headers[.contentType] = "application/json; charset=utf-8"
        let buffer = ByteBuffer(bytes: data)
        return Response(
            status: status,
            headers: headers,
            body: ResponseBody(byteBuffer: buffer)
        )
    }

    static func error(code: String, message: String, status: HTTPResponse.Status) -> Response {
        struct ErrorBody: Encodable {
            let code: String
            let message: String
        }
        do {
            return try make(ErrorBody(code: code, message: message), status: status)
        } catch {
            var headers = HTTPFields()
            headers[.contentType] = "application/json; charset=utf-8"
            let raw = "{\"code\":\"INTERNAL\",\"message\":\"failed to encode error\"}"
            return Response(
                status: .internalServerError,
                headers: headers,
                body: ResponseBody(byteBuffer: ByteBuffer(string: raw))
            )
        }
    }
}
