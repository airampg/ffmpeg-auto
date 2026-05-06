import Foundation
import Logging
@preconcurrency import FFmpegAutoCore

public struct JobLogSnapshot: Sendable {
    public let replay: String
    public let status: JobStatus
    public let totalDurationSeconds: Double?
    public let currentTimeSeconds: Double?
}

public actor JobOrchestrator {
    private let configuration: Configuration
    private let store: JobStore
    private let uploadStore: UploadStore
    private let validator: ValidationService
    private let commandBuilder: FFmpegCommandBuilder
    private let runner: FFmpegRunning
    private let probe: FFmpegProbe
    private let probeService: ProbeService?
    private let logger: Logger

    private var queue: [UUID] = []
    private var running: Set<UUID> = []
    private var broadcasters: [UUID: LogBroadcaster] = [:]
    private var handles: [UUID: FFmpegProcessHandle] = [:]
    private var cancelRequested: Set<UUID> = []

    public init(
        configuration: Configuration,
        store: JobStore,
        uploadStore: UploadStore,
        validator: ValidationService = ValidationService(),
        commandBuilder: FFmpegCommandBuilder = FFmpegCommandBuilder(),
        runner: FFmpegRunning = FFmpegRunner(),
        probe: FFmpegProbe,
        probeService: ProbeService?,
        logger: Logger
    ) {
        self.configuration = configuration
        self.store = store
        self.uploadStore = uploadStore
        self.validator = validator
        self.commandBuilder = commandBuilder
        self.runner = runner
        self.probe = probe
        self.probeService = probeService
        self.logger = logger
    }

    public func createJob(
        originalFilename: String,
        fileBytes: Data,
        settings: AudioConversionSettings,
        segmentMinutes: Int
    ) async throws -> UUID {
        if queue.count + running.count >= configuration.maxQueuedJobs {
            throw APIError.jobQueueFull
        }

        let id = UUID()
        let safeName = UploadStore.sanitizeFilename(originalFilename)
        let dirs = try await catchingStorage { try await self.uploadStore.prepareJobDirectories(id) }
        let inputURL = try await catchingStorage {
            try await self.uploadStore.writeUpload(jobID: id, sanitizedFilename: safeName, data: fileBytes)
        }

        let job = Job(
            id: id,
            originalFilename: originalFilename,
            inputFileURL: inputURL,
            outputFolderURL: dirs.outputDir,
            settings: settings,
            segmentMinutes: segmentMinutes
        )
        await store.insert(job)
        queue.append(id)
        broadcasters[id] = LogBroadcaster()
        logger.info("job queued", metadata: ["jobId": .string(id.uuidString)])
        Task { await self.dispatch() }
        return id
    }

    public func cancel(_ id: UUID) async {
        if let index = queue.firstIndex(of: id) {
            queue.remove(at: index)
            await store.update(id) { job in
                job.status = .cancelled
                job.finishedAt = Date()
            }
            await uploadStore.removeJob(id)
            await broadcastTerminal(id, status: .cancelled)
            logger.info("job cancelled (queued)", metadata: ["jobId": .string(id.uuidString)])
            return
        }
        if running.contains(id) {
            cancelRequested.insert(id)
            if let handle = handles[id] {
                await handle.terminate()
                logger.info("job cancel SIGTERM sent", metadata: ["jobId": .string(id.uuidString)])
                let escalation = handle
                Task.detached {
                    try? await Task.sleep(for: .seconds(5))
                    await escalation.forceKill()
                }
            }
        }
    }

    public func deleteFinishedJob(_ id: UUID) async throws {
        guard let job = await store.get(id) else {
            throw APIError.jobNotFound
        }
        switch job.status {
        case .running, .queued:
            await cancel(id)
        case .succeeded, .failed, .cancelled:
            break
        }
        await uploadStore.removeJob(id)
        await store.delete(id)
        if let broadcaster = broadcasters.removeValue(forKey: id) {
            await broadcaster.close()
        }
    }

    public func snapshot(_ id: UUID) async -> JobLogSnapshot? {
        guard let job = await store.get(id) else { return nil }
        return JobLogSnapshot(
            replay: job.logBuffer.content,
            status: job.status,
            totalDurationSeconds: job.totalDurationSeconds,
            currentTimeSeconds: job.currentTimeSeconds
        )
    }

    public func subscribe(_ id: UUID) async -> (subID: UUID, stream: AsyncStream<JobEvent>)? {
        guard let broadcaster = broadcasters[id] else { return nil }
        let result = await broadcaster.subscribe()
        return (subID: result.id, stream: result.stream)
    }

    public func unsubscribe(_ id: UUID, _ subID: UUID) async {
        await broadcasters[id]?.unsubscribe(subID)
    }

    private func dispatch() async {
        while running.count < configuration.maxConcurrentJobs, let nextID = queue.first {
            queue.removeFirst()
            running.insert(nextID)
            Task.detached { [weak self] in
                guard let self else { return }
                await self.runJob(nextID)
                await self.markFinished(nextID)
                await self.dispatch()
            }
        }
    }

    private func markFinished(_ id: UUID) {
        running.remove(id)
    }

    private func runJob(_ id: UUID) async {
        guard let initial = await store.get(id) else { return }
        await store.update(id) { job in
            job.status = .running
            job.startedAt = Date()
        }
        await broadcasters[id]?.broadcast(.status(.running))
        logger.info("job running", metadata: ["jobId": .string(id.uuidString)])

        guard let ffmpegURL = await probe.executableURL() else {
            await markFailed(id, message: "ffmpeg executable not available in container.")
            return
        }

        let location = FFmpegLocation(executableURL: ffmpegURL, checkedPaths: [ffmpegURL.path])
        let context = ValidationContext(
            inputFile: initial.inputFileURL,
            outputFolder: initial.outputFolderURL,
            segmentMinutesText: String(initial.segmentMinutes),
            ffmpegLocation: location,
            settings: initial.settings
        )

        let conversion: ValidatedConversion
        do {
            conversion = try validator.validate(context)
        } catch let error as AppValidationError {
            await markFailed(id, message: error.errorDescription ?? "Validation failed.")
            return
        } catch {
            await markFailed(id, message: error.localizedDescription)
            return
        }

        var probedDuration: Double?
        if let probeService {
            probedDuration = await probeService.probeDuration(of: conversion.inputFile)
        }

        if let probedDuration {
            do {
                try validator.validateTrim(settings: conversion.settings, probedDuration: probedDuration)
            } catch let error as AppValidationError {
                await markFailed(id, message: error.errorDescription ?? "Trim validation failed.")
                return
            } catch {
                await markFailed(id, message: error.localizedDescription)
                return
            }
        }

        // For progress reporting we want the total duration to reflect the clip
        // ffmpeg actually produces, not the source file. With -ss before -i, ffmpeg
        // emits 0-based output timestamps so currentTime is already clip-relative.
        let effectiveDuration = conversion.effectiveDurationSeconds(probedDuration: probedDuration) ?? probedDuration
        await store.update(id) { $0.totalDurationSeconds = effectiveDuration }

        let command = commandBuilder.build(from: conversion)
        let display = commandBuilder.displayTemplate(for: conversion)
        await store.update(id) { $0.commandDisplay = display }

        let processHandle = FFmpegProcessHandle()
        handles[id] = processHandle

        let store = self.store
        let logger = self.logger
        let parserActor = ProgressParserActor()
        let broadcaster = broadcasters[id]
        let totalDuration = await store.get(id)?.totalDurationSeconds

        let result: FFmpegResult
        do {
            result = try await runner.run(command: command, processHandle: processHandle) { @Sendable text in
                Task {
                    await store.update(id) { $0.logBuffer.append(text) }
                    await broadcaster?.broadcast(.log(text))
                    let times = await parserActor.ingest(text)
                    if let last = times.last {
                        await store.update(id) { $0.currentTimeSeconds = last }
                        let percent: Double?
                        if let total = totalDuration, total > 0 {
                            percent = min((last / total) * 100, 100)
                        } else {
                            percent = nil
                        }
                        await broadcaster?.broadcast(.progress(
                            percent: percent,
                            currentTimeSeconds: last,
                            totalDurationSeconds: totalDuration
                        ))
                    }
                }
            }
        } catch {
            logger.error("job error during run", metadata: [
                "jobId": .string(id.uuidString),
                "error": .string(error.localizedDescription)
            ])
            await markFailed(id, message: error.localizedDescription)
            return
        }

        handles.removeValue(forKey: id)

        if cancelRequested.contains(id) {
            cancelRequested.remove(id)
            await store.update(id) { job in
                job.status = .cancelled
                job.finishedAt = Date()
            }
            await uploadStore.removeJob(id)
            await broadcastTerminal(id, status: .cancelled)
            logger.info("job cancelled (running)", metadata: ["jobId": .string(id.uuidString)])
            return
        }

        if result.exitCode == 0 {
            let outputs = await uploadStore.listOutputs(id)
            await store.update(id) { job in
                job.status = .succeeded
                job.finishedAt = Date()
                job.outputs = outputs
                job.currentTimeSeconds = job.totalDurationSeconds
            }
            await broadcastTerminal(id, status: .succeeded)
            logger.info("job succeeded", metadata: [
                "jobId": .string(id.uuidString),
                "outputCount": .stringConvertible(outputs.count)
            ])
        } else {
            let stderr = Self.lastMeaningfulLine(from: result.stderr)
            let message = "ffmpeg exited with code \(result.exitCode). \(stderr.isEmpty ? "No error details." : stderr)"
            await markFailed(id, message: message)
        }
    }

    public func pruneFinishedJobsOlderThan(_ cutoff: Date) async {
        let removable = await store.pruneFinished(olderThan: cutoff)
        for id in removable {
            await uploadStore.removeJob(id)
            if let broadcaster = broadcasters.removeValue(forKey: id) {
                await broadcaster.close()
            }
        }
        if !removable.isEmpty {
            logger.info("retention prune", metadata: ["count": .stringConvertible(removable.count)])
        }
    }

    private func markFailed(_ id: UUID, message: String) async {
        let isCancelled: Bool = await {
            guard let current = await store.get(id) else { return false }
            return current.status == .cancelled
        }()
        if isCancelled {
            await broadcastTerminal(id, status: .cancelled)
            return
        }
        await store.update(id) { job in
            job.status = .failed
            job.errorMessage = message
            job.finishedAt = Date()
        }
        await broadcastTerminal(id, status: .failed)
        logger.warning("job failed", metadata: [
            "jobId": .string(id.uuidString),
            "message": .string(message)
        ])
    }

    private func broadcastTerminal(_ id: UUID, status: JobStatus) async {
        guard let broadcaster = broadcasters[id] else { return }
        await broadcaster.broadcast(.status(status))
        await broadcaster.close()
        broadcasters.removeValue(forKey: id)
    }

    private func catchingStorage<T: Sendable>(_ block: @Sendable () async throws -> T) async throws -> T {
        do {
            return try await block()
        } catch let err as UploadError {
            switch err {
            case .tooLarge(let limit):
                throw APIError.uploadTooLarge(limit: limit)
            case .ioError(let reason):
                throw APIError.storageError(reason)
            }
        } catch {
            throw APIError.storageError(error.localizedDescription)
        }
    }

    private static func lastMeaningfulLine(from stderr: String) -> String {
        stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty } ?? ""
    }
}

private actor ProgressParserActor {
    private var parser = ProgressParser()
    func ingest(_ text: String) -> [Double] { parser.ingest(text) }
}
