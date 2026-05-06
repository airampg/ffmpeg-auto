import Foundation

public struct Configuration: Sendable {
    public let port: Int
    public let workdir: URL
    public let maxConcurrentJobs: Int
    public let maxQueuedJobs: Int
    public let maxUploadBytes: Int64
    public let jobRetentionHours: Int
    public let logLevel: String

    public static func load() -> Configuration {
        let env = ProcessInfo.processInfo.environment
        return Configuration(
            port: env.intValue("PORT", default: 9090),
            workdir: URL(fileURLWithPath: env["WORKDIR"] ?? "/workdir"),
            maxConcurrentJobs: env.intValue("MAX_CONCURRENT_JOBS", default: 1),
            maxQueuedJobs: env.intValue("MAX_QUEUED_JOBS", default: 20),
            maxUploadBytes: env.int64Value("MAX_UPLOAD_BYTES", default: 4_294_967_296),
            jobRetentionHours: env.intValue("JOB_RETENTION_HOURS", default: 24),
            logLevel: env["LOG_LEVEL"] ?? "info"
        )
    }
}

private extension Dictionary where Key == String, Value == String {
    func intValue(_ key: String, default fallback: Int) -> Int {
        guard let raw = self[key], let value = Int(raw) else { return fallback }
        return value
    }
    func int64Value(_ key: String, default fallback: Int64) -> Int64 {
        guard let raw = self[key], let value = Int64(raw) else { return fallback }
        return value
    }
}
