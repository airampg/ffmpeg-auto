import Foundation
import Hummingbird
import Logging
@preconcurrency import FFmpegAutoCore

@main
struct FFmpegAutoServerEntry {
    static func main() async throws {
        let configuration = Configuration.load()
        LoggingSetup.bootstrap(level: configuration.logLevel)
        let logger = Logger(label: "ffmpeg-auto-server")
        logger.info("Booting", metadata: [
            "port": .stringConvertible(configuration.port),
            "workdir": .string(configuration.workdir.path),
            "maxConcurrentJobs": .stringConvertible(configuration.maxConcurrentJobs)
        ])

        try ensureWorkdir(at: configuration.workdir)

        let probe = FFmpegProbe()
        let version = await probe.version()
        logger.info("ffmpeg located", metadata: ["version": .string(version)])

        let probeService: ProbeService?
        if let ffmpegURL = await probe.executableURL() {
            probeService = ProbeService(ffmpegURL: ffmpegURL)
        } else {
            probeService = nil
        }

        let store = JobStore()
        let uploadStore = UploadStore(
            workdir: configuration.workdir,
            maxUploadBytes: configuration.maxUploadBytes
        )
        let orchestrator = JobOrchestrator(
            configuration: configuration,
            store: store,
            uploadStore: uploadStore,
            probe: probe,
            probeService: probeService,
            logger: logger
        )

        let validator = ValidationService()
        let router = buildRouter(
            configuration: configuration,
            probe: probe,
            orchestrator: orchestrator,
            store: store,
            uploadStore: uploadStore,
            workdir: configuration.workdir,
            validator: validator
        )

        let retentionTask = startRetentionTask(
            orchestrator: orchestrator,
            configuration: configuration,
            logger: logger
        )

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname("0.0.0.0", port: configuration.port),
                serverName: "FFmpegAutoServer"
            ),
            logger: logger
        )

        do {
            try await app.runService()
        } catch {
            retentionTask.cancel()
            throw error
        }
        retentionTask.cancel()
    }

    private static func ensureWorkdir(at url: URL) throws {
        let fm = FileManager.default
        let uploads = url.appendingPathComponent("uploads")
        let outputs = url.appendingPathComponent("outputs")
        try fm.createDirectory(at: uploads, withIntermediateDirectories: true)
        try fm.createDirectory(at: outputs, withIntermediateDirectories: true)
    }
}
