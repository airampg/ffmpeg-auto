# SPEC — Trim de audio/video antes de procesar

> Estado: borrador inicial. Pendiente: validación con dueño + decisiones marcadas con `[?]`.
> Branch sugerida: `feature/trim`
> Depende de: `feature/web-docker` (frontal web ya operativo).

---

## 1. Objetivo

Permitir al usuario **recortar** un fragmento del archivo subido (audio o video) en el navegador **antes** de que el servidor lo procese con ffmpeg. El recorte se hace por puntos `start` y `end` en segundos (precisión sub-segundo) y se aplica como primer paso del pipeline ffmpeg en el servidor.

Caso de uso típico: subir una grabación de 90 minutos y procesar solo el tramo `00:12:30 → 00:45:00` para luego segmentarlo en chunks de 15 min para transcripción.

### 1.1 Principios

- **Fuente de verdad en el servidor**: el recorte real lo aplica ffmpeg en el contenedor, no el navegador. Evitamos depender de WASM ffmpeg en el cliente.
- **Tipado fuerte**: el trim viaja como dos `Double` opcionales (`trimStartSeconds`, `trimEndSeconds`) en el `JobSubmitDTO`, no como texto libre dentro de `extraFFmpegArguments`.
- **Cero impacto si no se usa**: si el usuario no toca el trim, el comportamiento es idéntico al actual.
- **Reuso del Core**: la construcción de los flags `-ss`/`-to` vive en `FFmpegCommandBuilder`, así que tanto la app macOS como la web los obtienen "gratis" cuando se decida exponerlos también en el cliente nativo.

### 1.2 Non-goals (fuera de scope)

- Recorte client-side con WASM ffmpeg para subir solo el clip. Subimos el archivo completo y recortamos en servidor.
- Edición avanzada: corte multi-rango, fundido entre clips, cortes que respeten frames I exactos. Solo un único intervalo `[start, end)`.
- Preview del clip recortado **post-procesamiento** (codec/container final aplicados). Solo preview del **rango** sobre el archivo original con los controles HTML5.
- Edición en la app macOS de escritorio. Esta spec cubre solo el flujo web. Cuando el dueño quiera, los mismos campos se exponen en `AppView.swift` reusando el `FFmpegCommandBuilder` ya extendido.
- Recorte por número de frame. Solo por timestamp en segundos.

---

## 2. User stories

1. **Como usuario web**, después de soltar un archivo y antes de pulsar "Start processing", quiero ver un reproductor del archivo y poder marcar "desde aquí" / "hasta aquí" para que el procesado solo cubra ese tramo.
2. **Como usuario web**, quiero ver claramente los timestamps de inicio y fin elegidos en formato `HH:MM:SS.mmm` y poder ajustarlos a mano si la posición del slider no es exacta.
3. **Como usuario web**, quiero poder previsualizar **solo** el tramo seleccionado (play desde `start`, parar al llegar a `end`) para verificar que es lo que quiero antes de enviar al backend.
4. **Como usuario web**, quiero que el spinner de progreso del job refleje el progreso del **clip** (% sobre `end - start`), no del archivo completo.
5. **Como devops**, no quiero romper el contrato JSON existente: clientes que no manden los nuevos campos siguen funcionando igual.

---

## 3. Arquitectura

### 3.1 Flujo

```
┌─────────────────┐      multipart       ┌────────────────────┐
│  Browser (SPA)  │ ───────────────────▶ │  api (Hummingbird) │
│                 │   file + settings    │                    │
│  ▶ UploadForm   │   { trimStart,       │  JobsHandler       │
│  ▶ MediaTrimmer │     trimEnd, ... }   │  → JobOrchestrator │
└─────────────────┘                      └─────────┬──────────┘
                                                   │
                                       FFmpegCommandBuilder
                                                   │
                                                   ▼
                              ffmpeg -ss S -i input -to E ... -f segment ...
```

### 3.2 Dónde encaja en el código existente

| Capa | Fichero | Cambio |
|---|---|---|
| Frontend | `web/src/components/MediaTrimmer.tsx` | **NUEVO** — reproductor + sliders. |
| Frontend | `web/src/components/UploadForm.tsx` | Compone `MediaTrimmer` entre dropzone y `SettingsAdvanced`. |
| Frontend | `web/src/api/types.ts` | Añade `trimStartSeconds?: number` y `trimEndSeconds?: number` a `JobSubmitSettings`. |
| Frontend | `web/src/api/jobs.ts` | Reenvía los campos sin transformación. |
| Backend | `Sources/FFmpegAutoServer/DTOs.swift` | Añade `trimStartSeconds: Double?`, `trimEndSeconds: Double?` a `JobSubmitDTO`. |
| Core | `Sources/FFmpegAutoCore/AppModels.swift` | Añade `trimStartSeconds: Double?`, `trimEndSeconds: Double?` a `AudioConversionSettings` y los propaga a `ValidatedConversion`. |
| Core | `Sources/FFmpegAutoCore/FFmpegCommandBuilder.swift` | Inserta `-ss <start>` antes de `-i` (fast-seek) y `-to <end>` justo después de `-i`. |
| Core | `Sources/FFmpegAutoCore/ValidationService.swift` | Valida coherencia (`0 <= start < end <= duration`, ambos finitos). |
| Backend | `Sources/FFmpegAutoServer/JobOrchestrator.swift` | Ajusta el cálculo de progreso para que `totalDurationSeconds` represente la duración del clip, no del archivo entero. |
| Tests | `Tests/FFmpegAutoServerTests/` | Tests unitarios para nuevos parsers y builder. |

---

## 4. Backend

### 4.1 DTO HTTP

```swift
public struct JobSubmitDTO: Codable, Sendable {
    // ... campos existentes ...
    public var trimStartSeconds: Double?
    public var trimEndSeconds: Double?
}
```

Ambos opcionales. Compatibilidad atrás garantizada: clientes que no los manden reciben el comportamiento previo.

### 4.2 Modelo de dominio

`AudioConversionSettings` gana dos campos opcionales, ambos en segundos como `Double`:

```swift
public struct AudioConversionSettings: Equatable {
    // ... existentes ...
    public var trimStartSeconds: Double?
    public var trimEndSeconds: Double?
}
```

`ValidatedConversion` los recoge tras validación. Si pasan los chequeos quedan como `Double` no opcionales en el modelo validado (`trimStartSeconds: Double` con valor 0 cuando no se aplicó).

### 4.3 Command builder — fast-seek

Decisión clave: **`-ss` va antes de `-i` siempre que sea posible**.

| Posición | Comportamiento | Velocidad | Precisión |
|---|---|---|---|
| `-ss` antes de `-i` | Input-seek: ffmpeg salta directamente al keyframe más cercano y empieza a decodificar desde ahí. | Muy rápida (segundos para archivos de GB). | Sub-segundo desde ffmpeg ≥4.0. Antes era a-keyframe; ya no. |
| `-ss` después de `-i` | Output-seek: ffmpeg decodifica todo desde el principio y descarta los frames hasta `-ss`. | Lenta. | Exacta al frame. |

Con ffmpeg ≥4.0 (la imagen del contenedor usa `ubuntu:24.04` → ffmpeg 6.x), `-ss` antes de `-i` ya es preciso al sub-segundo. **No necesitamos `-accurate_seek`** (es default desde 4.0).

`-to` siempre va **después de `-i`**. Es relativo al input cuando va con `-ss` antes de `-i`, así que `-to 90` significa "para a los 90s del archivo original", no "90s después del start".

Si `trimStart > 0` y `trimEnd > 0`:

```
ffmpeg -ss 750.5 -i input.mp4 -to 2700.0 ... -f segment ...
```

Si solo hay `trimEnd`:

```
ffmpeg -i input.mp4 -to 2700.0 ...
```

Si solo hay `trimStart`:

```
ffmpeg -ss 750.5 -i input.mp4 ...
```

Implementación en `FFmpegCommandBuilder`:

```swift
public func build(from conversion: ValidatedConversion) -> FFmpegCommand {
    var arguments: [String] = []

    if let start = conversion.trimStartSeconds, start > 0 {
        arguments += ["-ss", formatSeconds(start)]
    }
    arguments += ["-i", conversion.inputFile.path]
    if let end = conversion.trimEndSeconds {
        arguments += ["-to", formatSeconds(end)]
    }

    // ... resto del build actual sin tocar ...
}

private func formatSeconds(_ value: Double) -> String {
    String(format: "%.3f", value)  // 0.001 s precision
}
```

### 4.4 Validación

`ValidationService` añade chequeos:

- `trimStartSeconds`, si presente: `>= 0` y finito.
- `trimEndSeconds`, si presente: `>= 0` y finito.
- Si ambos presentes: `start < end` y `end - start >= 1.0` (no permitimos clips de menos de 1 segundo).
- Si conocemos la duración real (vía `FFmpegProbe.probe(path:)`, que ya existe): `end <= duration + 0.5` (tolerancia para errores de redondeo). Si no la conocemos por probe, no validamos contra el final.

Errores nuevos en `AppValidationError`:

```swift
case trimStartNegative
case trimEndNotAfterStart
case trimEndBeyondDuration(duration: Double, end: Double)
case trimRangeTooShort(minimumSeconds: Double)
```

### 4.5 Progreso

`JobOrchestrator` actualmente calcula `percent = currentTime / totalDuration * 100`. Con trim, el `currentTime` que reporta ffmpeg es relativo al **inicio del clip** (no del archivo), pero el `totalDuration` que sacamos de `FFmpegProbe` es del archivo entero. Hay que ajustar:

```swift
let effectiveDuration: Double
if let start = job.trimStartSeconds, let end = job.trimEndSeconds {
    effectiveDuration = end - start
} else if let end = job.trimEndSeconds, let total = probedDuration {
    effectiveDuration = end
} else if let start = job.trimStartSeconds, let total = probedDuration {
    effectiveDuration = total - start
} else {
    effectiveDuration = probedDuration ?? 0
}
```

Y reportar `totalDurationSeconds = effectiveDuration` en `JobDetailResponse.progress`.

---

## 5. Frontend

### 5.1 Componente `MediaTrimmer`

Nuevo componente standalone. Props:

```ts
interface MediaTrimmerProps {
  file: File;
  value: { startSeconds: number | null; endSeconds: number | null };
  onChange: (value: { startSeconds: number | null; endSeconds: number | null }) => void;
}
```

Comportamiento:

- Crea un `URL.createObjectURL(file)` y lo libera en cleanup (efecto con `useEffect` y `revokeObjectURL`).
- Detecta tipo: si `file.type.startsWith("video/")` renderiza `<video controls>`, si no `<audio controls>`.
- Espera al evento `loadedmetadata` para conocer `duration`. Hasta entonces muestra "Loading metadata…".
- Dos sliders sincronizados: `start` (0..duration) y `end` (0..duration), con paso de 0.1 s.
- Un display formateado al lado de cada slider: `HH:MM:SS.mmm`.
- Botón "Use current as start" / "Use current as end" que toman `videoRef.current.currentTime`.
- Botón "Reset" que pone `start = 0`, `end = duration` y emite `onChange({ startSeconds: null, endSeconds: null })` (no enviar campos al backend si todo el archivo).
- Botón "Preview clip" que:
  1. Hace seek al `start`.
  2. Inicia `play()`.
  3. Suscribe a `timeupdate` y pausa cuando `currentTime >= end`.
  4. Quita el listener al pausar.
- Indicador visual sobre la timeline: una banda translúcida cubriendo el rango `[start, end]` por encima de los controles del `<video>`. Usar un `<div>` posicionado `absolute` con `left = (start/duration)*100%`, `width = ((end-start)/duration)*100%`. (Opcional para v1; ver §8 fases.)

Reglas de UX:

- Si el usuario sube un archivo nuevo, se resetea el trim.
- Si el clip resultante quedaría < 1 s, deshabilitar "Start processing" y mostrar warning.
- Si `start >= end`, lo mismo.
- El componente acepta valores fuera de los sliders (input numérico manual): el usuario puede teclear `00:01:23.500` en un input al lado del slider.

### 5.2 Formato de datos al enviar

En `UploadForm.tsx`:

```ts
const trimStartSeconds = trim.startSeconds && trim.startSeconds > 0 ? trim.startSeconds : undefined;
const trimEndSeconds = trim.endSeconds && trim.endSeconds < duration ? trim.endSeconds : undefined;

mutation.mutate({
  file,
  settings: { ...settings, trimStartSeconds, trimEndSeconds },
  onUploadProgress: ...
});
```

Si el usuario no tocó nada, ambos quedan `undefined` y el JSON serializado no los incluye → backend ignora.

### 5.3 Tipado TS

```ts
export interface JobSubmitSettings {
  // ... campos existentes ...
  trimStartSeconds?: number;
  trimEndSeconds?: number;
}
```

### 5.4 Layout en `UploadForm`

Orden visual:

1. Dropzone (existente).
2. **MediaTrimmer** (nuevo) — solo visible si `file != null`.
3. `SettingsAdvanced` (existente).
4. Botón "Start processing" + barra de progreso de upload.

### 5.5 Accesibilidad

- Sliders con `aria-label="Trim start"` / `"Trim end"`.
- Inputs numéricos con `inputMode="numeric"` y máscara `HH:MM:SS.mmm`.
- Botones con `type="button"` para no enviar el form.
- El reproductor mantiene los controles nativos del navegador (subtítulos, volumen, fullscreen).

---

## 6. Edge cases

| Caso | Comportamiento esperado |
|---|---|
| Archivo sin metadata de duración detectable por el navegador | `MediaTrimmer` muestra error "Cannot read media duration. Trim disabled." y no expone los sliders. El usuario sigue pudiendo procesar el archivo entero. |
| Audio puro (mp3, m4a, wav, ogg, opus) | Se renderiza `<audio>` en vez de `<video>`. Resto idéntico. |
| Archivo con video pero sin audio | Se renderiza `<video>`. La conversión sigue siendo válida si el usuario marca `audioOnly = false`. Caso raro pero posible. |
| Archivo con metadata "live" (HLS, MPEG-DASH) | El navegador puede reportar `duration = Infinity`. Detectar y deshabilitar trim, mismo mensaje que el caso de "sin metadata". |
| `trimEnd > duration` reportado por probe | `ValidationService` lo rechaza con `trimEndBeyondDuration`. El frontend ya debería evitarlo, esto es defensa en profundidad. |
| Clip de < 1 s | Validación rechaza con `trimRangeTooShort`. UI deshabilita el botón antes de llegar al backend. |
| Trim "todo el archivo" (start=0, end=duration) | UI emite `undefined` para ambos campos. Backend procesa archivo entero, comportamiento legacy. |
| Decimales agresivos (`12.987654321`) | Frontend redondea a 3 decimales antes de enviar. Backend acepta cualquier `Double`. ffmpeg recibe `12.988`. |
| Codec sin keyframes regulares (PCM) y `-ss` antes de `-i` | No aplica: PCM siempre es decodificable desde cualquier punto. Sin problemas. |
| Codec con keyframes muy espaciados (vídeos de cámara antiguos) | ffmpeg ≥4.0 reanaliza los frames intermedios para precisión sub-segundo. Penalización de tiempo despreciable comparada con output-seek. |
| Job cancelado a mitad de clip | Mismo comportamiento actual: el orchestrator manda SIGTERM, los outputs parciales se mantienen. |
| Restart del contenedor con job en cola que tenía trim | El upload original se conserva en el volumen y el job se rehidrata con sus settings (ya funciona así, los nuevos campos viajan en el snapshot). |

---

## 7. Pruebas

### 7.1 Tests Swift (`Tests/FFmpegAutoServerTests/`)

```swift
final class TrimCommandBuilderTests: XCTestCase {
    func test_noTrim_buildsClassicCommand() { ... }
    func test_trimStartOnly_addsSsBeforeInput() { ... }
    func test_trimEndOnly_addsToAfterInput() { ... }
    func test_bothTrim_ssBeforeInputToAfterInput() { ... }
    func test_trimStartZero_omitsSs() { ... }
    func test_subSecondPrecision_formatsThreeDecimals() { ... }
}

final class TrimValidationTests: XCTestCase {
    func test_negativeStart_throws() { ... }
    func test_endNotAfterStart_throws() { ... }
    func test_rangeTooShort_throws() { ... }
    func test_endBeyondProbedDuration_throws() { ... }
}

final class TrimDTORoundtripTests: XCTestCase {
    func test_decodeWithoutTrimFields_succeeds() { ... }
    func test_decodeWithTrimFields_preservesValues() { ... }
}
```

### 7.2 Tests TS (`web/src/`)

```ts
describe("MediaTrimmer", () => {
  it("renders <video> for video mime types", ...)
  it("renders <audio> for audio mime types", ...)
  it("disables sliders when duration is Infinity", ...)
  it("clamps end to duration on input", ...)
  it("emits null/null on Reset", ...)
  it("formats current time as HH:MM:SS.mmm", ...)
  it("preview clip stops at end", ...)
})
```

### 7.3 Test manual end-to-end

1. Subir un mp4 de 10 minutos.
2. Marcar `start=02:30.000`, `end=03:30.000`.
3. Pulsar "Preview clip" → debe reproducir 1 minuto y parar.
4. Pulsar "Start processing" con `segmentMinutes=1`.
5. Verificar que el job genera **un solo** segmento de ~1 min.
6. Repetir sin trim sobre el mismo archivo → debe generar **10 segmentos**.

---

## 8. Fases de implementación

### Fase 1 — Backend (sin frontend cambiado)

- [ ] DTO + AudioConversionSettings + ValidatedConversion con campos opcionales.
- [ ] `FFmpegCommandBuilder` con `-ss` y `-to`.
- [ ] `ValidationService` con nuevos errores.
- [ ] `JobOrchestrator` ajusta progreso.
- [ ] Tests Swift.
- [ ] Verificar con `curl` mandando JSON con trim que ffmpeg corta correctamente.

### Fase 2 — Frontend MVP

- [ ] Tipos en `web/src/api/types.ts`.
- [ ] `MediaTrimmer.tsx` con sliders + display + Preview Clip.
- [ ] Integración en `UploadForm.tsx`.
- [ ] Tests TS.

### Fase 3 — UX polish (opcional, no bloqueante)

- [ ] Banda translúcida sobre la timeline del player.
- [ ] Atajos de teclado (`s` = set start, `e` = set end, `space` = play/pause, `r` = reset).
- [ ] Input manual `HH:MM:SS.mmm` con máscara y validación inline.
- [ ] Mostrar duración del clip resultante destacada (`Clip duration: 1:00.000`).

### Fase 4 — Reuso en macOS (futuro, no en este PR)

- [ ] Exponer los mismos campos en `AppView.swift`.
- [ ] Tests en `FFmpegAutoCoreTestRunner`.

---

## 9. Decisiones abiertas `[?]`

- `[?]` **Mínimo de duración del clip**: propuesto 1.0 s. ¿Suficiente?
- `[?]` **Formato del display**: `HH:MM:SS.mmm` siempre, o `MM:SS.mmm` cuando duración < 1h. Yo iría a "siempre HH:MM:SS.mmm" por consistencia.
- `[?]` **Encoding del clip a precisión exacta**: ¿se acepta la imprecisión de keyframe-seek con ffmpeg ≥4.0 (que en la práctica es <1 frame) o se prefiere forzar output-seek con la penalización de tiempo? Recomendado: input-seek por defecto.
- `[?]` **Probe síncrono al subir**: ¿ejecutar `ffprobe` durante el upload para conocer la duración real y validar `trimEnd <= duration` antes de empezar a procesar? Coste: ~200ms extra. Beneficio: feedback inmediato si el usuario manipula el JSON. Recomendado: sí.
- `[?]` **Soporte de trim en formato `HH:MM:SS`**: el DTO usa `Double` (segundos). El frontend convierte. ¿Aceptamos también string `HH:MM:SS` por API para clientes externos cómodos? Recomendado: no, mantener tipado estricto. Si alguien quiere usar la API a mano, que convierta.

---

## 10. Riesgos

| Riesgo | Mitigación |
|---|---|
| Discrepancia entre `duration` reportada por el navegador y `ffprobe` (por bugs de container parsing) | Validar en backend contra ffprobe. UI sólo informa. |
| Browser cuelga reproduciendo archivos muy grandes desde `URL.createObjectURL` | Documentar en docs/README que el preview client-side requiere RAM proporcional al tamaño del archivo. Para ficheros >2GB el browser puede negarse — el trim sigue funcionando, solo se pierde la preview. |
| ffmpeg con `-ss` antes de `-i` produce output con timestamps desplazados (`-reset_timestamps 1` ya está) | El builder actual ya añade `-reset_timestamps 1`. No se cambia. |
| El usuario espera precisión a frame y obtiene precisión a sub-segundo | Documentar en la UI con un tooltip: "Trim precision: ~10 ms. For frame-accurate cuts, use the desktop app's advanced flags." |
