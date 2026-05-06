import Foundation
import FFmpegAutoCore

public actor FFmpegProbe {
    private var cachedVersion: String?
    private var cachedExecutable: URL?
    private let locator: FFmpegLocating

    public init(locator: FFmpegLocating = FFmpegLocator()) {
        self.locator = locator
    }

    public func version() async -> String {
        if let cachedVersion { return cachedVersion }
        let location = locator.locateFFmpeg(overridePath: nil)
        guard let url = location.executableURL else {
            cachedVersion = "unavailable"
            return "unavailable"
        }
        cachedExecutable = url
        let firstLine = await Self.runVersion(executableURL: url)
        cachedVersion = firstLine
        return firstLine
    }

    public func executableURL() async -> URL? {
        _ = await version()
        return cachedExecutable
    }

    private static func runVersion(executableURL: URL) async -> String {
        await Task.detached { () -> String in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executableURL
            process.arguments = ["-version"]
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                if let first = text.split(separator: "\n", maxSplits: 1).first {
                    return String(first)
                }
                return "unknown"
            } catch {
                return "error: \(error.localizedDescription)"
            }
        }.value
    }
}
