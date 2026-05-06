import Foundation

public enum JobEvent: Sendable {
    case log(String)
    case progress(percent: Double?, currentTimeSeconds: Double?, totalDurationSeconds: Double?)
    case status(JobStatus)
    case end
}

public actor LogBroadcaster {
    private var continuations: [UUID: AsyncStream<JobEvent>.Continuation] = [:]
    private var closed: Bool = false

    public init() {}

    public func subscribe() -> (id: UUID, stream: AsyncStream<JobEvent>) {
        let id = UUID()
        let (stream, continuation) = AsyncStream<JobEvent>.makeStream()
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.unsubscribe(id) }
        }
        if closed {
            continuation.finish()
        } else {
            continuations[id] = continuation
        }
        return (id, stream)
    }

    public func unsubscribe(_ id: UUID) {
        continuations.removeValue(forKey: id)?.finish()
    }

    public func broadcast(_ event: JobEvent) {
        guard !closed else { return }
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    public func close() {
        closed = true
        for continuation in continuations.values {
            continuation.yield(.end)
            continuation.finish()
        }
        continuations.removeAll()
    }
}

public extension JobStatus {
    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled: return true
        case .queued, .running: return false
        }
    }
}
