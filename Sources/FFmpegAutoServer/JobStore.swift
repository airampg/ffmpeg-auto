import Foundation

public actor JobStore {
    private var jobs: [UUID: Job] = [:]

    public init() {}

    public func insert(_ job: Job) {
        jobs[job.id] = job
    }

    public func get(_ id: UUID) -> Job? {
        jobs[id]
    }

    public func update(_ id: UUID, _ mutate: (inout Job) -> Void) {
        guard var job = jobs[id] else { return }
        mutate(&job)
        jobs[id] = job
    }

    public func delete(_ id: UUID) {
        jobs.removeValue(forKey: id)
    }

    public func list(limit: Int = 50) -> [Job] {
        jobs.values
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    public func pruneFinished(olderThan threshold: Date) -> [UUID] {
        let removable = jobs.values.filter { job in
            switch job.status {
            case .succeeded, .failed, .cancelled:
                return (job.finishedAt ?? job.createdAt) < threshold
            case .queued, .running:
                return false
            }
        }.map(\.id)
        for id in removable { jobs.removeValue(forKey: id) }
        return removable
    }
}
