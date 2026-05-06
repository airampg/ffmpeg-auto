import Foundation
import Logging

public func startRetentionTask(
    orchestrator: JobOrchestrator,
    configuration: Configuration,
    logger: Logger
) -> Task<Void, Never> {
    Task.detached(priority: .background) {
        let interval: TimeInterval = 3600
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            if Task.isCancelled { break }
            let cutoff = Date().addingTimeInterval(-Double(configuration.jobRetentionHours) * 3600)
            await orchestrator.pruneFinishedJobsOlderThan(cutoff)
            logger.debug("retention cycle", metadata: ["cutoff": .string(ISO8601DateFormatter().string(from: cutoff))])
        }
    }
}
