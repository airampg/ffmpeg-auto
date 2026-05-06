import Foundation

public struct FFmpegLocator: FFmpegLocating {
    public init() {}

    public func locateFFmpeg(overridePath: String? = nil) -> FFmpegLocation {
        var checkedPaths: [String] = []

        if let overridePath, !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let candidate = URL(fileURLWithPath: overridePath.trimmingCharacters(in: .whitespacesAndNewlines))
            checkedPaths.append(candidate.path)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return FFmpegLocation(executableURL: candidate, checkedPaths: checkedPaths)
            }
        }

        for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg"] {
            checkedPaths.append(path)
            if FileManager.default.isExecutableFile(atPath: path) {
                return FFmpegLocation(executableURL: URL(fileURLWithPath: path), checkedPaths: checkedPaths)
            }
        }

        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathValue.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("ffmpeg")
            checkedPaths.append(candidate.path)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return FFmpegLocation(executableURL: candidate, checkedPaths: checkedPaths)
            }
        }
        return FFmpegLocation(executableURL: nil, checkedPaths: checkedPaths)
    }
}

public final class FFmpegRunner: FFmpegRunning {
    public init() {}

    public func run(command: FFmpegCommand, logHandler: @escaping @Sendable (String) -> Void) async throws -> FFmpegResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let capture = OutputCapture()

            process.executableURL = command.executableURL
            process.arguments = command.arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let append: @Sendable (Data, Bool) -> Void = { data, isStdErr in
                guard !data.isEmpty else { return }
                let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                capture.append(text, isStdErr: isStdErr)
                logHandler(text)
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { append($0.availableData, false) }
            stderrPipe.fileHandleForReading.readabilityHandler = { append($0.availableData, true) }

            process.terminationHandler = { finishedProcess in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                append(stdoutPipe.fileHandleForReading.readDataToEndOfFile(), false)
                append(stderrPipe.fileHandleForReading.readDataToEndOfFile(), true)
                let snapshot = capture.snapshot()
                let result = FFmpegResult(exitCode: finishedProcess.terminationStatus, stdout: snapshot.stdout, stderr: snapshot.stderr)
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class OutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = ""
    private var stderr = ""

    func append(_ text: String, isStdErr: Bool) {
        lock.lock()
        if isStdErr { stderr += text } else { stdout += text }
        lock.unlock()
    }

    func snapshot() -> (stdout: String, stderr: String) {
        lock.lock()
        let value = (stdout, stderr)
        lock.unlock()
        return value
    }
}
