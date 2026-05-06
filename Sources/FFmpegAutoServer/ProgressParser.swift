import Foundation

public struct ProgressParser: Sendable {
    private var carry: String = ""

    public init() {}

    public mutating func ingest(_ chunk: String) -> [Double] {
        var buffer = carry + chunk
        var results: [Double] = []
        while let separator = buffer.firstIndex(where: { $0 == "\r" || $0 == "\n" }) {
            let line = String(buffer[..<separator])
            if let seconds = Self.extractTime(from: line) {
                results.append(seconds)
            }
            buffer = String(buffer[buffer.index(after: separator)...])
        }
        carry = buffer
        return results
    }

    public static func extractTime(from line: String) -> Double? {
        guard let range = line.range(
            of: #"time=(\d{1,3}):([0-5]\d):([0-5]\d(?:\.\d+)?)"#,
            options: .regularExpression
        ) else { return nil }
        let match = String(line[range])
        let components = match.dropFirst("time=".count).split(separator: ":")
        guard components.count == 3,
              let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}
