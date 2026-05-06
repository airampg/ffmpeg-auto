# FFmpegAuto

Segment audio/video files with ffmpeg into chunks of a fixed duration, with sane defaults for transcription pipelines.

Two front-ends share the same Swift core:

- **macOS app** — native SwiftUI GUI. Open `Package.swift` in Xcode, run the `FFmpegAuto` scheme.
- **Web app** — React SPA + Swift HTTP server in Docker. Multiplatform, runs anywhere Docker runs.

This README covers the **web/Docker** path. For the macOS app see the source in `Sources/FFmpegAutoApp`.

---

## Run on Docker

Requirements: **Docker Desktop ≥ 24** (Linux containers, WSL2 backend on Windows).

```bash
docker compose up --build
```

Open <http://localhost:8080>. Drop an audio or video file, hit *Start processing*, watch logs stream live, download outputs as a zip or one by one.

The first build pulls `swift:6.0-jammy` and `ubuntu:24.04`, takes 3–5 minutes. Subsequent builds are incremental.

### Stack

```
┌─ ffmpeg-auto-web (nginx:alpine) ────────────┐
│  Serves SPA, proxies /api → api:9090        │
│  Port 8080 exposed on host                  │
└──────────────────┬──────────────────────────┘
                   │ proxy_buffering off
                   ▼
┌─ ffmpeg-auto-api (ubuntu:24.04 + ffmpeg) ───┐
│  Hummingbird HTTP server                    │
│  Reuses Sources/FFmpegAutoCore/* unchanged  │
│  Volume: workdir → /workdir                 │
└─────────────────────────────────────────────┘
```

### Environment (api container)

| Variable | Default | What it does |
|---|---|---|
| `PORT` | `9090` | Listen port (kept inside the network). |
| `WORKDIR` | `/workdir` | Where uploads + outputs live. |
| `MAX_CONCURRENT_JOBS` | `1` | How many ffmpeg jobs run in parallel. |
| `MAX_QUEUED_JOBS` | `20` | Total queue depth before 503. |
| `MAX_UPLOAD_BYTES` | `4294967296` (4 GB) | Per-upload cap. |
| `JOB_RETENTION_HOURS` | `24` | Finished jobs and their files are pruned after this. |
| `LOG_LEVEL` | `info` | `trace`/`debug`/`info`/`warning`/`error`. |

---

## Develop on the web app

You'll want Node 20+ and Docker for the api side.

```bash
# Run the api in a container (also installs ffmpeg, ffprobe, zip):
docker compose up --build api

# Vite dev server with proxy → api:
cd web
npm install
npm run dev
```

Vite serves at <http://localhost:5173>; `/api/*` requests are proxied to the api container at port 9090 (mapped to host) — see `vite.config.ts`. Edit React, hot reload, see results.

---

## Develop on the api (Swift)

The api is a Swift Package executable using [Hummingbird 2](https://github.com/hummingbird-project/hummingbird) and [MultipartKit](https://github.com/vapor/multipart-kit). On macOS:

```bash
swift run FFmpegAutoServer
```

On Linux (or Windows host without Swift toolchain):

```bash
docker run --rm -v "$PWD:/src" -w /src swift:6.0-jammy swift run FFmpegAutoServer
```

The cross-platform Core lives in `Sources/FFmpegAutoCore/`. macOS-specific code (`SystemServices`, `AppViewModel`) lives in `Sources/FFmpegAutoCoreMac/` and is conditionally excluded from non-macOS builds via `Package.swift`.

### Tests

```bash
# Server tests (cross-platform, run on Linux):
docker run --rm -v "$PWD:/src" -w /src swift:6.0-jammy swift test

# Frontend tests:
cd web && npm test

# macOS app + Core tests (macOS only):
swift run FFmpegAutoCoreTestRunner
```

---

## API

All endpoints are JSON unless stated. See `docs/SPEC-web-docker.md` §4 for the full contract.

| Method | Path | Notes |
|---|---|---|
| `GET` | `/api/v1/health` | Liveness + ffmpeg version. |
| `GET` | `/api/v1/capabilities` | Codec/container/sample rate options. |
| `POST` | `/api/v1/jobs` | `multipart/form-data`: `settings` (JSON) + `file` (binary). |
| `GET` | `/api/v1/jobs` | Recent jobs (last 50). |
| `GET` | `/api/v1/jobs/:id` | Job detail with progress + outputs. |
| `DELETE` | `/api/v1/jobs/:id` | Cancel running job (SIGTERM → SIGKILL after 5 s) or delete finished. |
| `GET` | `/api/v1/jobs/:id/outputs/:name` | Download a single segment. |
| `GET` | `/api/v1/jobs/:id/outputs.zip` | Stream all segments as a zip. |
| `GET` | `/api/v1/jobs/:id/logs` | `text/event-stream` — replay + live log + progress + status. |

Errors return `{ "code": "STRING", "message": "..." }` with the HTTP status documented in `docs/SPEC-web-docker.md` §7.

---

## Project layout

```
ffmpeg-auto/
├── Package.swift              Swift package manifest. macOS-only targets gated by #if os(macOS).
├── Sources/
│   ├── FFmpegAutoCore/        Cross-platform: validation, command builder, naming, runner.
│   ├── FFmpegAutoCoreMac/     macOS-only: AppKit + Combine code (Finder, trash, ObservableObject view model).
│   ├── FFmpegAutoApp/         macOS SwiftUI app.
│   ├── FFmpegAutoCoreTestRunner/  macOS-only test runner (uses AppViewModel).
│   └── FFmpegAutoServer/      Cross-platform Hummingbird server.
├── Tests/
│   └── FFmpegAutoServerTests/ Server unit tests (XCTest).
├── web/                        React 19 + Vite + TypeScript + Tailwind 4 SPA.
├── docker/
│   ├── api/Dockerfile          Multi-stage swift:6.0-jammy → ubuntu:24.04.
│   └── web/{Dockerfile,nginx.conf}  Multi-stage node:20 → nginx:alpine.
├── docker-compose.yml          Two services + named volume.
└── docs/
    └── SPEC-web-docker.md      Architecture spec; the source of truth for design decisions.
```

---

## Out of scope (intentional)

- **HTTPS / TLS**. Put behind a reverse proxy (Caddy, Traefik, …) if you expose this beyond localhost.
- **Auth**. Single-user local-only by default. The handler layout has one obvious place to inject a bearer-token middleware if you need it later.
- **Persistence of jobs across restarts**. Lists are in memory; uploads and outputs live on a Docker named volume and are pruned by `JOB_RETENTION_HOURS`. Restarting the api drops in-flight jobs; their volume files are pruned on the next retention cycle.
- **Remote URL ingestion** (yt-dlp etc.). Upload only.

See `docs/SPEC-web-docker.md` §13–14 for rationale and §15 for the planned cutover roadmap.

---

## License

Same as upstream `airampg/ffmpeg-auto`.
