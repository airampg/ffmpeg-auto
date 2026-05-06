import { useEffect, useMemo, useRef, useState } from "react";
import clsx from "clsx";
import { formatSecondsPrecise, parseTimecode } from "../lib/format";
import { probeMedia } from "../api/jobs";
import { ScissorsIcon, PlayIcon, ResetIcon, SpinnerIcon, AlertIcon } from "../lib/icons";

const MIN_CLIP_SECONDS = 1.0;
const BROWSER_PROBE_TIMEOUT_MS = 2500;

export interface TrimRange {
  startSeconds: number | null;
  endSeconds: number | null;
}

interface Props {
  file: File;
  value: TrimRange;
  onChange: (next: TrimRange) => void;
  onDurationLoaded?: (durationSeconds: number) => void;
}

export function MediaTrimmer({ file, value, onChange, onDurationLoaded }: Props) {
  const mediaRef = useRef<HTMLVideoElement | HTMLAudioElement | null>(null);
  const probeAbortRef = useRef<AbortController | null>(null);
  const probeFallbackTimerRef = useRef<number | null>(null);
  const [objectUrl, setObjectUrl] = useState<string | null>(null);
  const [duration, setDuration] = useState<number | null>(null);
  const [durationError, setDurationError] = useState<string | null>(null);
  const [serverProbeProgress, setServerProbeProgress] = useState<number | null>(null);
  const [currentTime, setCurrentTime] = useState(0);
  const [isPreviewing, setIsPreviewing] = useState(false);

  const isVideo = file.type.startsWith("video/");

  useEffect(() => {
    const url = URL.createObjectURL(file);
    setObjectUrl(url);
    setDuration(null);
    setDurationError(null);
    setServerProbeProgress(null);
    setCurrentTime(0);
    onChange({ startSeconds: null, endSeconds: null });
    return () => {
      URL.revokeObjectURL(url);
      probeAbortRef.current?.abort();
      probeAbortRef.current = null;
      if (probeFallbackTimerRef.current != null) {
        window.clearTimeout(probeFallbackTimerRef.current);
        probeFallbackTimerRef.current = null;
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [file]);

  // Some containers (m4a/mp4 with the MOOV box at the end, VBR mp3 without a Xing
  // header, etc.) make the browser report `Infinity` or a wrong estimated duration on
  // `loadedmetadata`. Seeking past the end forces the decoder to scan to EOF and
  // emit `durationchange` with the real value.
  const tryForceDurationDiscovery = () => {
    const media = mediaRef.current;
    if (!media) return;
    if (Number.isFinite(media.duration) && media.duration > 0) return;
    try {
      media.currentTime = 1e9;
    } catch {
      // Ignore — some browsers throw when seeking before any data is loaded.
    }
  };

  const acceptDuration = (d: number) => {
    if (!Number.isFinite(d) || d <= 0) return false;
    setDuration(d);
    setDurationError(null);
    setServerProbeProgress(null);
    if (probeFallbackTimerRef.current != null) {
      window.clearTimeout(probeFallbackTimerRef.current);
      probeFallbackTimerRef.current = null;
    }
    probeAbortRef.current?.abort();
    probeAbortRef.current = null;
    onDurationLoaded?.(d);
    return true;
  };

  const scheduleServerProbeFallback = () => {
    if (probeFallbackTimerRef.current != null) return;
    probeFallbackTimerRef.current = window.setTimeout(() => {
      probeFallbackTimerRef.current = null;
      void runServerProbe();
    }, BROWSER_PROBE_TIMEOUT_MS);
  };

  const runServerProbe = async () => {
    if (probeAbortRef.current) return;
    const controller = new AbortController();
    probeAbortRef.current = controller;
    setServerProbeProgress(0);
    try {
      const result = await probeMedia(
        file,
        (fraction) => setServerProbeProgress(fraction),
        controller.signal
      );
      if (controller.signal.aborted) return;
      if (result.durationSeconds != null && Number.isFinite(result.durationSeconds) && result.durationSeconds > 0) {
        acceptDuration(result.durationSeconds);
      } else {
        setServerProbeProgress(null);
        setDurationError(
          "Server could not determine the media duration. Trim editing is disabled, but you can still process the full file."
        );
      }
    } catch {
      if (controller.signal.aborted) return;
      setServerProbeProgress(null);
      setDurationError(
        "Server probe failed. Trim editing is disabled, but you can still process the full file."
      );
    } finally {
      if (probeAbortRef.current === controller) {
        probeAbortRef.current = null;
      }
    }
  };

  const onLoadedMetadata = () => {
    const media = mediaRef.current;
    if (!media) return;
    if (!acceptDuration(media.duration)) {
      tryForceDurationDiscovery();
      scheduleServerProbeFallback();
    }
  };

  const onDurationChange = () => {
    const media = mediaRef.current;
    if (!media) return;
    if (acceptDuration(media.duration)) {
      // Reset playhead to 0 if we had to seek-to-EOF to discover the duration.
      if (media.currentTime > media.duration) {
        media.currentTime = 0;
      }
    }
  };

  const onTimeUpdate = () => {
    const media = mediaRef.current;
    if (!media) return;
    setCurrentTime(media.currentTime);
    if (isPreviewing && value.endSeconds != null && media.currentTime >= value.endSeconds) {
      media.pause();
      setIsPreviewing(false);
    }
  };

  const onPause = () => setIsPreviewing(false);

  const effectiveStart = value.startSeconds ?? 0;
  const effectiveEnd = value.endSeconds ?? duration ?? 0;
  const clipDuration = duration != null ? Math.max(0, effectiveEnd - effectiveStart) : 0;
  const clipTooShort = duration != null && clipDuration < MIN_CLIP_SECONDS;
  const isFullRange = value.startSeconds == null && value.endSeconds == null;

  const setStart = (next: number | null) => {
    onChange({ ...value, startSeconds: next });
  };
  const setEnd = (next: number | null) => {
    onChange({ ...value, endSeconds: next });
  };

  const useCurrentAsStart = () => {
    if (duration == null) return;
    setStart(roundMs(currentTime));
  };
  const useCurrentAsEnd = () => {
    if (duration == null) return;
    setEnd(roundMs(currentTime));
  };

  const reset = () => {
    onChange({ startSeconds: null, endSeconds: null });
    if (mediaRef.current) mediaRef.current.currentTime = 0;
  };

  const previewClip = () => {
    const media = mediaRef.current;
    if (!media || duration == null) return;
    media.currentTime = effectiveStart;
    setIsPreviewing(true);
    void media.play().catch(() => setIsPreviewing(false));
  };

  // Keyboard shortcuts: only when the trimmer is focused, to avoid clashing
  // with native form controls.
  const containerRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    const node = containerRef.current;
    if (!node) return;
    const handler = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      const tag = target?.tagName.toLowerCase();
      if (tag === "input" || tag === "textarea" || tag === "select") return;
      if (e.key === "s") { e.preventDefault(); useCurrentAsStart(); }
      else if (e.key === "e") { e.preventDefault(); useCurrentAsEnd(); }
      else if (e.key === "r") { e.preventDefault(); reset(); }
      else if (e.key === "p") { e.preventDefault(); previewClip(); }
    };
    node.addEventListener("keydown", handler);
    return () => node.removeEventListener("keydown", handler);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [duration, value.startSeconds, value.endSeconds, currentTime]);

  return (
    <div
      ref={containerRef}
      tabIndex={0}
      className="surface-card p-5 space-y-4 outline-none focus:ring-2 focus:ring-[var(--color-accent-glow)] animate-fade-in-up"
    >
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2.5">
          <div className="grid place-items-center w-8 h-8 rounded-lg bg-[var(--color-accent-soft)] text-[var(--color-accent)]">
            <ScissorsIcon size={16} />
          </div>
          <div>
            <h3 className="text-sm font-semibold text-zinc-100">Trim</h3>
            <p className="text-xs text-zinc-500">Optionally select a section to process.</p>
          </div>
        </div>
        {duration != null && (
          <div className="text-right">
            <div className="text-[10px] uppercase tracking-wider text-zinc-500">Clip</div>
            <div className={clsx(
              "font-mono text-sm",
              clipTooShort ? "text-rose-400" : "text-zinc-100"
            )}>
              {formatSecondsPrecise(clipDuration)}
              <span className="text-zinc-600"> / {formatSecondsPrecise(duration)}</span>
            </div>
          </div>
        )}
      </div>

      <div className="media-frame">
        {isVideo ? (
          <video
            ref={mediaRef as React.RefObject<HTMLVideoElement>}
            src={objectUrl ?? undefined}
            onLoadedMetadata={onLoadedMetadata}
            onDurationChange={onDurationChange}
            onTimeUpdate={onTimeUpdate}
            onPause={onPause}
            controls
            preload="metadata"
            className="w-full max-h-80 bg-black"
          />
        ) : (
          <audio
            ref={mediaRef as React.RefObject<HTMLAudioElement>}
            src={objectUrl ?? undefined}
            onLoadedMetadata={onLoadedMetadata}
            onDurationChange={onDurationChange}
            onTimeUpdate={onTimeUpdate}
            onPause={onPause}
            controls
            preload="metadata"
            className="w-full bg-[#0a0a0d] py-3 px-2"
          />
        )}
      </div>

      {durationError && (
        <div className="rounded-lg bg-amber-500/[0.07] border border-amber-500/25 px-3 py-2 flex items-start gap-2 text-xs text-amber-200">
          <AlertIcon size={14} className="text-amber-400 flex-shrink-0 mt-0.5" />
          <span>{durationError}</span>
        </div>
      )}

      {!durationError && duration == null && serverProbeProgress == null && (
        <div className="text-xs text-zinc-500 inline-flex items-center gap-2">
          <SpinnerIcon size={14} />
          Loading media metadata…
        </div>
      )}

      {!durationError && duration == null && serverProbeProgress != null && (
        <div className="text-xs text-zinc-400 inline-flex items-center gap-2">
          <SpinnerIcon size={14} className="text-[var(--color-accent)]" />
          Browser couldn't read duration · probing on server {(serverProbeProgress * 100).toFixed(0)}%
        </div>
      )}

      {duration != null && (
        <>
          <TimelineBand
            duration={duration}
            currentTime={currentTime}
            startSeconds={effectiveStart}
            endSeconds={effectiveEnd}
            onSeek={(s) => {
              if (mediaRef.current) mediaRef.current.currentTime = s;
            }}
          />

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <TrimEndpoint
              label="Start"
              seconds={effectiveStart}
              maxSeconds={Math.max(0, effectiveEnd - MIN_CLIP_SECONDS)}
              onSeconds={(v) => setStart(v <= 0 ? null : v)}
              onUseCurrent={useCurrentAsStart}
              isExplicit={value.startSeconds != null}
            />
            <TrimEndpoint
              label="End"
              seconds={effectiveEnd}
              maxSeconds={duration}
              minSeconds={Math.min(duration, effectiveStart + MIN_CLIP_SECONDS)}
              onSeconds={(v) => setEnd(v >= duration ? null : v)}
              onUseCurrent={useCurrentAsEnd}
              isExplicit={value.endSeconds != null}
            />
          </div>

          <div className="flex flex-wrap items-center gap-2 pt-1">
            <button
              type="button"
              onClick={previewClip}
              disabled={clipTooShort}
              className="btn-ghost inline-flex items-center gap-1.5 text-xs"
            >
              <PlayIcon size={12} />
              Preview clip
            </button>
            <button
              type="button"
              onClick={reset}
              disabled={isFullRange}
              className="btn-ghost inline-flex items-center gap-1.5 text-xs"
            >
              <ResetIcon size={12} />
              Reset
            </button>
            {clipTooShort && (
              <span className="text-xs text-rose-400 inline-flex items-center gap-1.5">
                <AlertIcon size={12} /> Min {MIN_CLIP_SECONDS.toFixed(1)}s
              </span>
            )}
            <div className="ml-auto flex items-center gap-1.5 text-[11px] text-zinc-500">
              <kbd className="key">S</kbd> start
              <kbd className="key">E</kbd> end
              <kbd className="key">P</kbd> preview
              <kbd className="key">R</kbd> reset
            </div>
          </div>
        </>
      )}
    </div>
  );
}

interface TrimEndpointProps {
  label: string;
  seconds: number;
  maxSeconds: number;
  minSeconds?: number;
  onSeconds: (next: number) => void;
  onUseCurrent: () => void;
  isExplicit: boolean;
}

function TrimEndpoint({
  label,
  seconds,
  maxSeconds,
  minSeconds = 0,
  onSeconds,
  onUseCurrent,
  isExplicit
}: TrimEndpointProps) {
  const [textValue, setTextValue] = useState(formatSecondsPrecise(seconds));
  const [isEditing, setIsEditing] = useState(false);

  useEffect(() => {
    if (!isEditing) setTextValue(formatSecondsPrecise(seconds));
  }, [seconds, isEditing]);

  const commit = () => {
    setIsEditing(false);
    const parsed = parseTimecode(textValue);
    if (parsed == null) {
      setTextValue(formatSecondsPrecise(seconds));
      return;
    }
    const clamped = Math.min(maxSeconds, Math.max(minSeconds, parsed));
    onSeconds(roundMs(clamped));
  };

  const sliderMax = useMemo(() => Math.max(maxSeconds, seconds), [maxSeconds, seconds]);

  return (
    <div className="space-y-2">
      <div className="flex items-baseline justify-between">
        <span className="text-[10px] uppercase tracking-[0.2em] text-zinc-500 font-medium">{label}</span>
        <span className={clsx(
          "text-[10px] uppercase tracking-wider",
          isExplicit ? "text-[var(--color-accent)]" : "text-zinc-600"
        )}>
          {isExplicit ? "● modified" : "default"}
        </span>
      </div>
      <input
        type="range"
        min={minSeconds}
        max={sliderMax}
        step={0.1}
        value={Math.min(sliderMax, Math.max(minSeconds, seconds))}
        onChange={(e) => onSeconds(roundMs(Number(e.target.value)))}
        className="slider-accent"
        aria-label={`${label} slider`}
      />
      <div className="flex items-center gap-2">
        <input
          type="text"
          value={textValue}
          onChange={(e) => { setTextValue(e.target.value); setIsEditing(true); }}
          onBlur={commit}
          onKeyDown={(e) => { if (e.key === "Enter") (e.target as HTMLInputElement).blur(); }}
          className="surface-input px-2.5 py-1.5 font-mono text-xs flex-1 min-w-0"
          aria-label={`Trim ${label.toLowerCase()} timestamp`}
        />
        <button
          type="button"
          onClick={onUseCurrent}
          className="btn-ghost text-xs whitespace-nowrap"
        >
          Use current
        </button>
      </div>
    </div>
  );
}

interface TimelineBandProps {
  duration: number;
  currentTime: number;
  startSeconds: number;
  endSeconds: number;
  onSeek?: (seconds: number) => void;
}

function TimelineBand({ duration, currentTime, startSeconds, endSeconds, onSeek }: TimelineBandProps) {
  if (duration <= 0) return null;
  const startPct = (startSeconds / duration) * 100;
  const widthPct = Math.max(0, ((endSeconds - startSeconds) / duration) * 100);
  const cursorPct = Math.min(100, Math.max(0, (currentTime / duration) * 100));

  const handleClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!onSeek) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const fraction = (e.clientX - rect.left) / rect.width;
    onSeek(Math.max(0, Math.min(duration, fraction * duration)));
  };

  return (
    <div
      className="relative h-2.5 bg-[var(--surface-1)] border border-[var(--border-subtle)] rounded-full overflow-hidden cursor-pointer group"
      onClick={handleClick}
      role="presentation"
    >
      {/* Selection band */}
      <div
        className="absolute inset-y-0 bg-gradient-to-r from-[var(--color-accent-soft)] via-[var(--color-accent-glow)] to-[var(--color-accent-soft)] transition-all"
        style={{ left: `${startPct}%`, width: `${widthPct}%` }}
        aria-hidden="true"
      />
      {/* Selection edges */}
      <div className="absolute inset-y-0 w-px bg-[var(--color-accent)]" style={{ left: `${startPct}%` }} aria-hidden="true" />
      <div className="absolute inset-y-0 w-px bg-[var(--color-accent)]" style={{ left: `${startPct + widthPct}%` }} aria-hidden="true" />
      {/* Playhead */}
      <div
        className="absolute -inset-y-1 w-0.5 bg-white shadow-[0_0_8px_rgba(255,255,255,0.5)]"
        style={{ left: `${cursorPct}%` }}
        aria-hidden="true"
      />
    </div>
  );
}

function roundMs(seconds: number): number {
  return Math.round(seconds * 1000) / 1000;
}
