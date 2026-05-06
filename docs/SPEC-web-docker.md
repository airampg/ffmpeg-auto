# SPEC — FFmpegAuto Web (Docker, multiplataforma)

> Estado: borrador inicial. Pendiente: validación con dueño + decisiones marcadas con `[?]`.
> Branch: `feature/web-docker`

---

## 1. Objetivo

Ofrecer la misma utilidad que la app macOS `FFmpegAuto` (segmentar audio/video con ffmpeg en chunks configurables, listo para transcripción) desde **cualquier sistema operativo** mediante un **frontal web servido en un contenedor Docker**.

La app macOS sigue existiendo y se mantiene como cliente nativo. La web es un **canal paralelo**, no un reemplazo.

### 1.1 Principios

- **Una sola fuente de verdad para la lógica de negocio**: validación, construcción de comando ffmpeg y naming se reutilizan tal cual desde `FFmpegAutoCore` (Swift). No reescribimos en Python/Node. Esto evita drift entre macOS y web.
- **Aislamiento total**: ffmpeg corre dentro del contenedor con su propio binario; el host no necesita tenerlo instalado.
- **Stateless por diseño**: el backend no persiste estado entre reinicios más allá de los ficheros en su volumen de trabajo. Sin BD.
- **Single-user local por defecto**: pensado para correr en `localhost`, sin auth. Multi-usuario y exposición pública quedan fuera del scope inicial (ver §13).

### 1.2 Non-goals (fuera de scope)

- Cuentas, login, multi-tenant.
- HTTPS / TLS termination (se asume detrás de un reverse proxy si se expone).
- Cluster / horizontal scaling. Una réplica.
- Soporte de jobs concurrentes ilimitados. Cola simple FIFO con concurrencia configurable (default 1).
- Mover originales a "papelera" (concepto que no aplica en web — el upload se borra al terminar según retention policy).
- Abrir carpetas en Finder/Explorer (concepto desktop).
- Sustituir la app macOS.

---

## 2. User stories

1. **Como usuario en Windows**, quiero subir un mp4 de 2 GB y obtener N ficheros m4a de 15 minutos cada uno, sin instalar ffmpeg ni Swift en mi máquina.
2. **Como usuario**, quiero ver logs de ffmpeg en tiempo real mientras procesa, igual que en la app macOS.
3. **Como usuario**, quiero descargar los segmentos como un único `.zip` o uno a uno desde el navegador.
4. **Como usuario**, quiero las mismas opciones avanzadas que la app macOS (codec, container, bitrate, sample rate, mono/stereo, segment minutes, filename prefix, loudnorm, extras ffmpeg).
5. **Como usuario**, quiero que un job que falla me dé el mensaje de error de ffmpeg sin tener que abrir la consola del contenedor.
6. **Como devops**, quiero un único `docker compose up` y tenerlo funcionando en `http://localhost:8080`.

---

## 3. Arquitectura

```
┌────────────────────────────────────────────────────────────────┐
│  Docker network (puente, interno)                              │
│                                                                │
│  ┌─────────────────────┐         ┌─────────────────────────┐   │
│  │  ffmpeg-auto-web    │         │  ffmpeg-auto-api        │   │
│  │  (nginx + SPA)      │ ──────▶ │  Swift + Hummingbird    │   │
│  │  Puerto 8080 (host) │  /api/* │  + ffmpeg embebido      │   │
│  │                     │  WS/SSE │  Puerto 9090 (interno)  │   │
│  └─────────────────────┘         └────────────┬────────────┘   │
│                                                │                │
│                                                ▼                │
│                                  ┌─────────────────────────┐   │
│                                  │  Volume: workdir        │   │
│                                  │   ├─ uploads/<job-id>/  │   │
│                                  │   └─ outputs/<job-id>/  │   │
│                                  └─────────────────────────┘   │
└────────────────────────────────────────────────────────────────┘
```

### 3.1 Contenedores

| Servicio | Imagen base | Responsabilidad |
|---|---|---|
| `ffmpeg-auto-api` | `swift:5.10-jammy` (build) → `ubuntu:24.04` (runtime) con `ffmpeg` apt-installed | API REST + WebSocket de logs. Ejecuta ffmpeg. |
| `ffmpeg-auto-web` | `node:20-alpine` (build SPA) → `nginx:1.27-alpine` (runtime) | Sirve la SPA estática + proxy `/api` → api. |

Una sola red bridge interna. Solo `ffmpeg-auto-web:8080` expuesto al host.

### 3.2 Volúmenes

- `ffmpegauto_workdir` (named volume) montado en `/workdir` dentro del contenedor api. Almacena uploads y outputs por job.

### 3.3 Por qué Swift + Hummingbird en el backend

Decisión clave. Justificación:

- **Reuso del Core**: `FFmpegAutoCore` (validación, command builder, naming, runner) es Foundation puro y compila en Linux con `swift build`. Solo hay que excluir `SystemServices.swift` (único fichero con `import AppKit`).
- **Hummingbird** es un framework HTTP minimalista para Swift on Linux, low-overhead, async/await nativo. Encaja con el estilo del Core (que ya usa `async/await`).
- **Alternativa descartada — Vapor**: válido pero pesado para esta API minimalista (4-5 endpoints). Hummingbird arranca en <100ms y es ~1/4 del binario.
- **Alternativa descartada — port a Python/FastAPI o Node/Express**: requiere reimplementar `FFmpegCommandBuilder`, `ValidationService`, `FileNamingService` en otro lenguaje → drift garantizado con cada cambio en la app macOS. Y multiplica los tests.

### 3.4 Reutilización de código

Modificación al `Package.swift` actual: añadir un nuevo target ejecutable `FFmpegAutoServer` que depende de `FFmpegAutoCore` + `Hummingbird`. Plataformas: además de `.macOS(.v14)`, añadir `.linux` implícito (los targets que no son la app GUI compilan en Linux).

`SystemServices.swift` (único fichero AppKit) se aísla con `#if canImport(AppKit)` o se mueve a un sub-target `FFmpegAutoCoreMac` que solo se compila en macOS, dejando `FFmpegAutoCore` estrictamente cross-platform.

```swift
// Package.swift (extracto futuro)
.target(name: "FFmpegAutoCore"),                          // cross-platform
.target(name: "FFmpegAutoCoreMac",                        // solo macOS
        dependencies: ["FFmpegAutoCore"],
        path: "Sources/FFmpegAutoCoreMac"),
.executableTarget(name: "FFmpegAutoApp",                  // la GUI macOS, sin cambios
                  dependencies: ["FFmpegAutoCore", "FFmpegAutoCoreMac"]),
.executableTarget(name: "FFmpegAutoServer",               // nuevo, solo Linux útil
                  dependencies: ["FFmpegAutoCore",
                                 .product(name: "Hummingbird", package: "hummingbird")]),
```

---

## 4. Backend API

### 4.1 Convenciones

- Todas las rutas bajo `/api/v1`.
- JSON request/response excepto upload (multipart) y descargas (binary).
- IDs de job: UUID v4.
- Timestamps en RFC3339.

### 4.2 Endpoints

| Método | Ruta | Propósito |
|---|---|---|
| `GET` | `/api/v1/health` | Liveness. Devuelve `{ status: "ok", ffmpegVersion: "..." }`. |
| `GET` | `/api/v1/capabilities` | Lista codecs/containers/sample rates soportados (espejo de `AppModels.swift` enums). El frontend no hardcodea. |
| `POST` | `/api/v1/jobs` | Crea un job. Multipart: `file` (binario) + `settings` (JSON con `AudioConversionSettings` + `segmentMinutes`). Devuelve `{ jobId, status: "queued" }`. |
| `GET` | `/api/v1/jobs/{id}` | Estado del job: `{ status, progress, command, errorMessage, outputCount, outputs: [{name,size}] }`. |
| `GET` | `/api/v1/jobs/{id}/logs` | SSE stream de logs ffmpeg en directo. |
| `GET` | `/api/v1/jobs/{id}/outputs.zip` | Descarga todos los segmentos en zip. Solo disponible si `status == "succeeded"`. |
| `GET` | `/api/v1/jobs/{id}/outputs/{name}` | Descarga un segmento individual. |
| `DELETE` | `/api/v1/jobs/{id}` | Cancela job (si running) y borra ficheros. |
| `GET` | `/api/v1/jobs` | Lista jobs recientes (en memoria, últimos 50). |

### 4.3 Schemas

```ts
// settings (POST /jobs, multipart "settings" field)
{
  segmentMinutes: number,           // 1..180
  audioOnly: boolean,               // default true
  codec: "aac"|"mp3"|"opus"|"pcmS16LE",
  container: "m4a"|"mp3"|"opus"|"wav",
  bitrate: string,                  // "48k", ignored si codec=pcm
  sampleRate: number,               // 8000|12000|16000|22050|24000|32000|44100|48000
  channels: 1|2,
  filenamePrefix: string,           // "meeting" default
  resetTimestamps: boolean,
  collisionPolicy: "failIfExists"|"overwriteMatchingSegments",
  loudnessNormalizationEnabled: boolean,
  extraFFmpegArguments: string      // se parsea con la misma rutina que la app macOS
  // ffmpegPathOverride: NO se acepta en web. El binario es el del contenedor.
}

// GET /jobs/{id}
{
  jobId: string,
  status: "queued"|"running"|"succeeded"|"failed"|"cancelled",
  createdAt: string,
  startedAt: string|null,
  finishedAt: string|null,
  inputFilename: string,
  command: string,                  // displayTemplate del Core
  progress: { percent: number|null, currentTimeSeconds: number|null },
  outputCount: number|null,
  outputs: { name: string, sizeBytes: number }[],
  errorMessage: string|null
}
```

### 4.4 Ciclo de vida del job

```
queued ──► running ──► succeeded
                  └──► failed
                  └──► cancelled
```

- **queued**: aceptado, fichero subido, esperando worker.
- **running**: worker invocó `FFmpegRunner.run`. Logs streaming activo.
- **succeeded**: `exitCode == 0`. Outputs listados, zip generable on-demand.
- **failed**: `exitCode != 0` o validación previa falló. `errorMessage` poblado.
- **cancelled**: `DELETE` recibido durante running. Proceso ffmpeg killed con SIGTERM, después SIGKILL si no muere en 5s.

### 4.5 Cola de jobs

- Estructura en memoria: `Deque<Job>` + un actor `JobOrchestrator`.
- Concurrencia configurable por env var `MAX_CONCURRENT_JOBS` (default `1`).
- Si arrancan varios jobs y la cola está llena, se queuean. No hay límite de cola hard, pero `MAX_QUEUED_JOBS=20` opcional para evitar abuso.

### 4.6 Progreso

ffmpeg no emite porcentaje nativo. Estrategia:
1. **Probe inicial**: al recibir el upload, ejecutamos `ffprobe -v quiet -show_entries format=duration -of csv=p=0 <file>` para obtener la duración total en segundos.
2. **Parser de stderr**: mientras corre, parseamos las líneas tipo `time=00:01:23.45` del stderr de ffmpeg → tiempo procesado.
3. **percent = currentTime / totalDuration * 100**.
4. Si la duración no se puede determinar (algunos streams), `percent = null` y solo emitimos `currentTimeSeconds`.

### 4.7 Logs (SSE)

- `GET /api/v1/jobs/{id}/logs` → `Content-Type: text/event-stream`.
- Eventos:
  - `event: log` `data: { line: "..." }`
  - `event: progress` `data: { percent, currentTimeSeconds }`
  - `event: status` `data: { status }` (cuando cambia)
  - `event: end` `data: {}` cuando job termina (cliente cierra conexión).
- Si el cliente se conecta a un job que ya empezó, **se replayan los logs acumulados** (cap 80k chars como el Core actual) y luego sigue en directo.

---

## 5. Frontend

### 5.1 Stack

- **React 19 + Vite 5 + TypeScript** (consistencia con `Test.Front.Newsletter`).
- **Tailwind CSS 4** para estilo.
- **TanStack Query** para fetching/caching de jobs.
- **Sin estado global** — local state + queries bastan.

### 5.2 Pantallas

```
┌─ /                       Home (form + lista de jobs recientes)
├─ /jobs/:id               Detalle de job (logs en directo, descarga)
└─ (no más rutas)
```

### 5.3 Componentes principales

- **`<UploadForm />`**: drag-and-drop file picker + form de settings (idéntico al sheet "Advanced" de la app macOS).
- **`<SettingsAdvanced />`**: collapse con todos los campos avanzados. Carga `/api/v1/capabilities` para los selects.
- **`<JobsList />`**: tabla de jobs (id corto, filename, status badge, fecha, acciones).
- **`<JobDetail />`**: log viewer estilo terminal (mono, autoscroll, virtualización si > 1000 líneas), barra de progreso, botón cancelar, botón descargar zip + lista de outputs individuales.
- **`<LogViewer />`**: consume SSE, muestra líneas con coloreo básico (errores en rojo si la línea contiene `Error` o `failed`).

### 5.4 Validación cliente

Espejo de `ValidationService.swift`. Para evitar duplicar reglas, el frontend hace **validación blanda** (UX: mostrar errores antes de enviar) pero la **autoritativa es el backend**. Reglas exactas:
- Segment minutes 1-180 entero.
- Bitrate `^[0-9]{2,4}k$` salvo `codec=pcm`.
- Sample rate ∈ lista del endpoint capabilities.
- Codec/container compatibles según matriz: `aac↔m4a, mp3↔mp3, opus↔opus, pcm↔wav`.
- Prefix sanitizable (al menos un alfanumérico tras sanitize).

### 5.5 Subida de ficheros grandes

- Multipart streaming. Sin chunked resumable por ahora (TUS protocol queda como mejora).
- Progress bar de upload con `XMLHttpRequest.upload.onprogress` o fetch streams.
- Limit del lado servidor: `MAX_UPLOAD_BYTES` env var, default 4 GB.

---

## 6. Docker

### 6.1 `docker-compose.yml`

```yaml
services:
  api:
    build: ./docker/api
    volumes:
      - workdir:/workdir
    environment:
      MAX_CONCURRENT_JOBS: 1
      MAX_UPLOAD_BYTES: 4294967296
      JOB_RETENTION_HOURS: 24
      WORKDIR: /workdir
      LOG_LEVEL: info
    restart: unless-stopped
    expose:
      - "9090"

  web:
    build: ./docker/web
    ports:
      - "8080:80"
    depends_on:
      - api
    restart: unless-stopped

volumes:
  workdir:
```

### 6.2 Dockerfiles

**`docker/api/Dockerfile`** (multi-stage):
```dockerfile
FROM swift:5.10-jammy AS build
WORKDIR /src
COPY Package.swift Package.resolved* ./
COPY Sources ./Sources
RUN swift build -c release --product FFmpegAutoServer --static-swift-stdlib

FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg ca-certificates tzdata && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/.build/release/FFmpegAutoServer /usr/local/bin/
EXPOSE 9090
ENTRYPOINT ["FFmpegAutoServer"]
```

**`docker/web/Dockerfile`**:
```dockerfile
FROM node:20-alpine AS build
WORKDIR /src
COPY web/package*.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /src/dist /usr/share/nginx/html
COPY docker/web/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

**`docker/web/nginx.conf`** (extracto): proxy `/api` y `/api/.../logs` (con `proxy_buffering off` para SSE) a `api:9090`.

### 6.3 Layout final del repo

```
ffmpeg-auto/
├── Package.swift                       (modificado: nuevo target Server + sub-target Mac)
├── Sources/
│   ├── FFmpegAutoCore/                 (sin cambios salvo extracción de SystemServices)
│   ├── FFmpegAutoCoreMac/              (nuevo: SystemServices.swift)
│   ├── FFmpegAutoApp/                  (sin cambios)
│   ├── FFmpegAutoCoreTestRunner/       (sin cambios)
│   └── FFmpegAutoServer/               (nuevo: Hummingbird + handlers)
│       ├── Main.swift
│       ├── Routes.swift
│       ├── JobOrchestrator.swift
│       ├── JobStore.swift
│       └── ProgressParser.swift
├── web/                                (nuevo: SPA React)
│   ├── package.json
│   ├── vite.config.ts
│   ├── tailwind.config.ts
│   ├── tsconfig.json
│   ├── index.html
│   └── src/
│       ├── main.tsx
│       ├── App.tsx
│       ├── pages/
│       ├── components/
│       ├── api/
│       └── styles/
├── docker/
│   ├── api/Dockerfile
│   └── web/{Dockerfile,nginx.conf}
├── docker-compose.yml
├── docs/
│   └── SPEC-web-docker.md              (este documento)
└── README.md                           (añadir sección "Run on Docker")
```

---

## 7. Validación y errores (mapping desde `AppValidationError`)

Cada error del Core mapea a un HTTP code y un payload `{ code, message, details? }`:

| Core error | HTTP | code |
|---|---|---|
| `missingInputFile` | 400 | `MISSING_INPUT` |
| `missingOutputFolder` | (n/a en web — output siempre `/workdir/outputs/<jobId>`) | — |
| `emptySegmentLength` | 400 | `INVALID_SEGMENT` |
| `nonNumericSegmentLength` | 400 | `INVALID_SEGMENT` |
| `segmentLengthTooSmall/Large` | 400 | `INVALID_SEGMENT_RANGE` |
| `missingFFmpeg` | 500 | `FFMPEG_NOT_AVAILABLE` (no debería pasar; significa contenedor mal construido) |
| `inputFileMissing/Unreadable` | 500 | `STORAGE_ERROR` |
| `existingOutputFiles` | (n/a — output dir per-job, siempre vacío) | — |
| `incompatibleCodecContainer` | 400 | `INCOMPATIBLE_CODEC` |
| `invalidBitrate` | 400 | `INVALID_BITRATE` |
| `invalidSampleRate` | 400 | `INVALID_SAMPLE_RATE` |
| `invalidFilenamePrefix` | 400 | `INVALID_PREFIX` |
| `invalidExtraFFmpegArguments` | 400 | `INVALID_EXTRAS` |

Errores web-only:
- `UPLOAD_TOO_LARGE` 413
- `JOB_NOT_FOUND` 404
- `JOB_QUEUE_FULL` 503
- `JOB_NOT_DOWNLOADABLE` 409 (zip pedido sobre job no `succeeded`)

---

## 8. Retention y cleanup

- Job termina (success/fail/cancelled) → empieza countdown `JOB_RETENTION_HOURS` (default 24h).
- Tarea periódica del orchestrator cada hora: borra `uploads/<jobId>/` y `outputs/<jobId>/` cuyo `finishedAt + retention < now`.
- Borra también jobs en memoria > 7 días aunque ya no tengan ficheros.

---

## 9. Diferencias intencionales con la app macOS

| Concepto macOS | Equivalente web |
|---|---|
| Pickear input file desde `NSOpenPanel` | Drag-and-drop / file input HTML |
| Pickear output folder | Eliminado — output siempre `/workdir/outputs/<jobId>` |
| `ffmpegPathOverride` | Eliminado — ffmpeg es el del contenedor |
| Abrir output en Finder | Lista de outputs descargables + botón "download zip" |
| Mover original a papelera | Eliminado — el upload se borra según retention |
| Logs en `TextEditor` SwiftUI | `<LogViewer />` con SSE |
| `@MainActor AppViewModel` | TanStack Query + componentes React |

---

## 10. Tests

- **Core (existente)**: `FFmpegAutoCoreTestRunner` ya cubre validación, command builder, naming. Sin cambios.
- **Server (nuevo)**: tests de integración en `Tests/FFmpegAutoServerTests/`:
  - Health endpoint.
  - POST jobs con settings inválidos → 400 con código correcto.
  - POST jobs válido → 202 + jobId, GET /jobs/{id} eventualmente `succeeded`.
  - DELETE durante running → status `cancelled`.
  - SSE logs delivery (smoke test).
- **Frontend**: Vitest + React Testing Library para componentes; un Playwright "happy path" e2e contra la stack docker-compose en CI.

---

## 11. CI/CD (futuro, fuera de scope inicial pero contemplado)

- GitHub Actions workflow:
  - `swift test` (cross-platform: macOS + ubuntu).
  - `npm test` en `web/`.
  - `docker buildx` ambas imágenes; push a GHCR si tag.
- No se publica ahora; solo se deja preparado el directorio `.github/workflows/` con un workflow de tests.

---

## 12. Roadmap por fases

| Fase | Entregable | Criterio de éxito |
|---|---|---|
| **F1 — Refactor Core para Linux** | `Package.swift` con sub-target `FFmpegAutoCoreMac`. CI verde en macOS y `swift build` OK desde un contenedor `swift:5.10-jammy`. | Compila el target server (vacío) en Linux. App macOS sigue corriendo. |
| **F2 — Server skeleton** | `FFmpegAutoServer` con `/health`, `/capabilities`. Dockerfile api funcionando. | `curl localhost:9090/health` devuelve OK desde el contenedor. |
| **F3 — Job pipeline** | `POST /jobs` + worker + `GET /jobs/{id}`. Sin SSE aún, polling. | Subir un mp3 y obtener segmentos en `/workdir/outputs`. |
| **F4 — SSE logs + progress** | Streaming de logs y progreso. | Cliente curl con `-N` ve líneas en directo. |
| **F5 — Frontend MVP** | SPA con upload + lista + detalle + descarga zip. Tailwind + Vite. | `docker compose up` y flujo completo desde navegador. |
| **F6 — Pulido** | Cancel job, retention task, validación cliente espejo, zip on-demand, error mapping. | Todos los errores del Core se ven en UI con mensaje útil. |
| **F7 — Tests + README** | Tests server, tests frontend smoke, README con instrucciones. | `make test` verde. Onboarding < 5 min. |

---

## 13. Seguridad y exposición pública (fuera de scope, documentado)

Por defecto, **localhost-only**. Si alguien quiere exponer:

- TLS: poner detrás de un reverse proxy (Caddy/Traefik) con cert automático.
- Auth: añadir un middleware de bearer token (env var `API_TOKEN`). El frontend lo lee de un cookie o de un input al inicio. **No implementado en F1-F7**, pero la API se diseña con un único punto de inyección de auth (`AuthMiddleware` que se puede activar por env).
- Rate limit: nada por defecto. Sugerencia: rate limit a nivel reverse proxy.
- File scanning: ninguno. El upload se asume confiable. Para multi-user añadir antivirus / sandbox.
- DoS por upload masivo: `MAX_UPLOAD_BYTES` y `MAX_QUEUED_JOBS` mitigan parcialmente.

---

## 14. Decisiones tomadas (cerradas 2026-05-06)

1. **Framework HTTP**: **Hummingbird** (descartado Vapor por overhead innecesario para 4-5 endpoints).
2. **URLs remotas como input**: **fuera de scope F1-F7**. Solo upload directo. Anotado como futuro (yt-dlp + URL ingestion).
3. **Persistencia de jobs entre reinicios**: **no**. Lista en memoria, ficheros en volumen. Sin SQLite. Si un reinicio mata jobs en curso, los outputs incompletos quedan en el volumen y se barren con el cleanup de retention.
4. **Branding del frontal**: **dark neutro estilo terminal**. No reusar paleta Simbiu — este proyecto no es producto Simbiu, es herramienta personal multiplataforma. Acentos color `#21b2a3`-style permitidos pero no obligatorios.
5. **Idioma UI**: **inglés**, consistente con app macOS y con `FFmpegAutoCore`.

---

## 15. Próximos pasos inmediatos tras aprobar este SPEC

1. Validar las 5 decisiones abiertas con el dueño.
2. Abrir issues por cada fase F1–F7.
3. Empezar F1 (refactor Core para Linux) — es el bloqueador de todo lo demás. Estimación: 1-2h.
4. F2 (skeleton server + Dockerfile api) — 2-3h.
5. F3 (job pipeline mínimo, sin SSE) — 4-6h.
