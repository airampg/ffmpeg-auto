import Foundation

public enum UploadError: Error, Sendable {
    case tooLarge(limit: Int64)
    case ioError(String)
}

public actor UploadStore {
    private let workdir: URL
    private let maxUploadBytes: Int64
    private let fileManager = FileManager.default

    public init(workdir: URL, maxUploadBytes: Int64) {
        self.workdir = workdir
        self.maxUploadBytes = maxUploadBytes
    }

    public var configuredMaxUploadBytes: Int64 { maxUploadBytes }

    public func prepareJobDirectories(_ id: UUID) throws -> (uploadDir: URL, outputDir: URL) {
        let uploadDir = workdir.appendingPathComponent("uploads").appendingPathComponent(id.uuidString)
        let outputDir = workdir.appendingPathComponent("outputs").appendingPathComponent(id.uuidString)
        try fileManager.createDirectory(at: uploadDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
        return (uploadDir, outputDir)
    }

    public func writeUpload(jobID: UUID, sanitizedFilename: String, data: Data) throws -> URL {
        if Int64(data.count) > maxUploadBytes {
            throw UploadError.tooLarge(limit: maxUploadBytes)
        }
        let dir = workdir.appendingPathComponent("uploads").appendingPathComponent(jobID.uuidString)
        let target = dir.appendingPathComponent(sanitizedFilename)
        do {
            try data.write(to: target)
        } catch {
            throw UploadError.ioError(error.localizedDescription)
        }
        return target
    }

    public func removeJob(_ id: UUID) {
        let uploadDir = workdir.appendingPathComponent("uploads").appendingPathComponent(id.uuidString)
        let outputDir = workdir.appendingPathComponent("outputs").appendingPathComponent(id.uuidString)
        try? fileManager.removeItem(at: uploadDir)
        try? fileManager.removeItem(at: outputDir)
    }

    public func listOutputs(_ id: UUID) -> [JobOutput] {
        let outputDir = workdir.appendingPathComponent("outputs").appendingPathComponent(id.uuidString)
        guard let names = try? fileManager.contentsOfDirectory(atPath: outputDir.path) else { return [] }
        return names.sorted().compactMap { name in
            let url = outputDir.appendingPathComponent(name)
            guard let attrs = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
            let size = (attrs[.size] as? Int64) ?? 0
            return JobOutput(name: name, sizeBytes: size)
        }
    }

    public func outputFileURL(_ id: UUID, name: String) -> URL? {
        let outputDir = workdir.appendingPathComponent("outputs").appendingPathComponent(id.uuidString)
        let target = outputDir.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: target.path) else { return nil }
        return target
    }

    public static func sanitizeFilename(_ raw: String) -> String {
        let base = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "..", with: "-")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? "upload" : base
    }
}
