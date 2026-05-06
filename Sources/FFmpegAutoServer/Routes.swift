import Foundation
import Hummingbird
@preconcurrency import FFmpegAutoCore

func buildRouter(
    configuration: Configuration,
    probe: FFmpegProbe,
    probeService: ProbeService?,
    orchestrator: JobOrchestrator,
    store: JobStore,
    uploadStore: UploadStore,
    workdir: URL,
    validator: ValidationService = ValidationService()
) -> Router<BasicRequestContext> {
    let router = Router(context: BasicRequestContext.self)

    let health = HealthHandler(probe: probe)
    let capabilities = CapabilitiesHandler(validator: validator)
    let jobs = JobsHandler(
        configuration: configuration,
        orchestrator: orchestrator,
        store: store,
        uploadStore: uploadStore,
        validator: validator
    )
    let logs = LogsHandler(store: store, orchestrator: orchestrator)
    let zip = ZipHandler(store: store, workdir: workdir)
    let probeHandler = ProbeHandler(
        configuration: configuration,
        probeService: probeService,
        workdir: workdir
    )

    router.get("/api/v1/health") { request, context in
        try await health.handle(request, context: context)
    }

    router.get("/api/v1/capabilities") { request, context in
        try await capabilities.handle(request, context: context)
    }

    router.post("/api/v1/probe") { request, context in
        try await probeHandler.probe(request, context: context)
    }

    router.post("/api/v1/jobs") { request, context in
        try await jobs.create(request, context: context)
    }

    router.get("/api/v1/jobs") { request, context in
        try await jobs.list(request, context: context)
    }

    router.get("/api/v1/jobs/:id") { request, context in
        try await jobs.detail(request, context: context)
    }

    router.delete("/api/v1/jobs/:id") { request, context in
        try await jobs.delete(request, context: context)
    }

    router.get("/api/v1/jobs/:id/outputs/:name") { request, context in
        try await jobs.downloadOutput(request, context: context)
    }

    router.get("/api/v1/jobs/:id/outputs.zip") { request, context in
        try await zip.handle(request, context: context)
    }

    router.get("/api/v1/jobs/:id/logs") { request, context in
        try await logs.handle(request, context: context)
    }

    return router
}
