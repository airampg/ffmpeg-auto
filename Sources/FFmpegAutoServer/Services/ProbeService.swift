import Foundation

public actor ProbeService {
    private let executable: URL

    public init?(ffmpegURL: URL) {
        let candidate = ffmpegURL.deletingLastPathComponent().appendingPathComponent("ffprobe")
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            self.executable = candidate
            return
        }
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for envDir in pathValue.split(separator: ":") {
            let url = URL(fileURLWithPath: String(envDir)).appendingPathComponent("ffprobe")
            if FileManager.default.isExecutableFile(atPath: url.path) {
                self.executable = url
                return
            }
        }
        return nil
    }

    public func probeDuration(of file: URL) async -> Double? {
        let executablePath = executable.path
        let inputPath = file.path
        return await Task.detached { () -> Double? in
            let process = Process()
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = [
                "-v", "quiet",
                "-show_entries", "format=duration",
                "-of", "csv=p=0",
                inputPath
            ]
            process.standardOutput = outPipe
            process.standardError = errPipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let text = (String(data: data, encoding: .utf8) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return Double(text)
            } catch {
                return nil
            }
        }.value
    }
}
