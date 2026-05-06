import { useEffect, useState } from "react";
import { useDropzone } from "react-dropzone";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import clsx from "clsx";
import { useCapabilities } from "../hooks/useCapabilities";
import { createJob, type CreateJobOptions } from "../api/jobs";
import { ApiError } from "../api/client";
import type { JobSubmitSettings } from "../api/types";
import { SettingsAdvanced } from "./SettingsAdvanced";
import { MediaTrimmer, type TrimRange } from "./MediaTrimmer";
import { formatBytes } from "../lib/format";
import {
  UploadCloudIcon,
  FileAudioIcon,
  FileVideoIcon,
  FileGenericIcon,
  XIcon,
  AlertIcon,
  PlayIcon
} from "../lib/icons";

const MIN_CLIP_SECONDS = 1.0;

export function UploadForm() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const capabilities = useCapabilities();
  const [file, setFile] = useState<File | null>(null);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [settings, setSettings] = useState<JobSubmitSettings | null>(null);
  const [trim, setTrim] = useState<TrimRange>({ startSeconds: null, endSeconds: null });

  useEffect(() => {
    if (!settings && capabilities.data) {
      const d = capabilities.data.defaultSettings;
      setSettings({
        segmentMinutes: d.segmentMinutes,
        codec: d.codec,
        container: d.container,
        bitrate: d.bitrate,
        sampleRate: d.sampleRate,
        channels: d.channels,
        filenamePrefix: d.filenamePrefix,
        resetTimestamps: d.resetTimestamps,
        loudnessNormalizationEnabled: d.loudnessNormalizationEnabled,
        extraFFmpegArguments: ""
      });
    }
  }, [capabilities.data, settings]);

  const mutation = useMutation({
    mutationFn: (opts: CreateJobOptions) => createJob(opts),
    onSuccess: (response) => {
      queryClient.invalidateQueries({ queryKey: ["jobs"] });
      navigate(`/jobs/${response.jobId}`);
    }
  });

  const dropzone = useDropzone({
    multiple: false,
    accept: { "audio/*": [], "video/*": [] },
    onDrop: (accepted) => {
      const next = accepted[0];
      if (next) {
        setFile(next);
        setTrim({ startSeconds: null, endSeconds: null });
      }
    }
  });

  const clipDuration =
    trim.startSeconds != null && trim.endSeconds != null
      ? trim.endSeconds - trim.startSeconds
      : null;
  const trimInvalid = clipDuration != null && clipDuration < MIN_CLIP_SECONDS;

  const submit = () => {
    if (!file || !settings || trimInvalid) return;
    setUploadProgress(0);
    const settingsToSend: JobSubmitSettings = {
      ...settings,
      trimStartSeconds: trim.startSeconds ?? undefined,
      trimEndSeconds: trim.endSeconds ?? undefined
    };
    mutation.mutate({
      file,
      settings: settingsToSend,
      onUploadProgress: (fraction) => setUploadProgress(fraction)
    });
  };

  const error = mutation.error instanceof ApiError ? mutation.error : null;

  return (
    <div className="space-y-5">
      {!file ? (
        <Dropzone dropzone={dropzone} />
      ) : (
        <FileCard file={file} onRemove={() => setFile(null)} />
      )}

      {file && (
        <MediaTrimmer file={file} value={trim} onChange={setTrim} />
      )}

      {capabilities.isLoading && (
        <p className="text-sm text-zinc-500 px-1">Loading capabilities…</p>
      )}
      {capabilities.error && (
        <ErrorBanner message="Could not load capabilities. Is the API running?" />
      )}

      {settings && capabilities.data && (
        <SettingsAdvanced
          capabilities={capabilities.data}
          value={settings}
          onChange={setSettings}
        />
      )}

      <div className="flex flex-wrap items-center gap-3 pt-2">
        <button
          type="button"
          onClick={submit}
          disabled={!file || !settings || mutation.isPending || trimInvalid}
          className="btn-primary inline-flex items-center gap-2"
        >
          {mutation.isPending ? (
            <>
              <span className="inline-block w-3.5 h-3.5 border-2 border-current border-t-transparent rounded-full animate-spin-slow" />
              Uploading {(uploadProgress * 100).toFixed(0)}%
            </>
          ) : (
            <>
              <PlayIcon size={14} />
              Start processing
            </>
          )}
        </button>
        {trimInvalid && (
          <span className="text-xs text-rose-400 inline-flex items-center gap-1.5">
            <AlertIcon size={14} /> Clip is too short to process
          </span>
        )}
      </div>

      {error && (
        <ErrorBanner message={error.message} code={error.code} />
      )}
    </div>
  );
}

function Dropzone({ dropzone }: { dropzone: ReturnType<typeof useDropzone> }) {
  return (
    <div
      {...dropzone.getRootProps()}
      className={clsx(
        "relative surface-card p-10 text-center cursor-pointer transition-all duration-200 group",
        dropzone.isDragActive
          ? "ring-2 ring-[var(--color-accent-glow)] border-[var(--color-accent)]"
          : "hover:bg-[var(--surface-2)]"
      )}
    >
      <input {...dropzone.getInputProps()} />
      <div
        className={clsx(
          "mx-auto grid place-items-center w-14 h-14 rounded-2xl mb-4 transition-all duration-200",
          dropzone.isDragActive
            ? "bg-[var(--color-accent-soft)] text-[var(--color-accent)] scale-110"
            : "bg-[var(--surface-3)] text-zinc-400 group-hover:text-zinc-200 group-hover:scale-105"
        )}
      >
        <UploadCloudIcon size={26} />
      </div>
      <p className="text-base font-medium text-zinc-200 mb-1">
        {dropzone.isDragActive ? "Drop the file here" : "Drop an audio or video file"}
      </p>
      <p className="text-sm text-zinc-500">
        or <span className="text-[var(--color-accent)] font-medium">click to browse</span>
      </p>
      <p className="text-xs text-zinc-600 mt-4">
        Supports mp3, m4a, wav, opus, mp4, mov · max 4 GB
      </p>
    </div>
  );
}

function FileCard({ file, onRemove }: { file: File; onRemove: () => void }) {
  const Icon = file.type.startsWith("audio/")
    ? FileAudioIcon
    : file.type.startsWith("video/")
      ? FileVideoIcon
      : FileGenericIcon;

  return (
    <div className="surface-card px-5 py-4 flex items-center gap-4 animate-fade-in-up">
      <div className="grid place-items-center w-11 h-11 rounded-lg bg-[var(--color-accent-soft)] text-[var(--color-accent)] flex-shrink-0">
        <Icon size={22} />
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-medium text-zinc-100 truncate">{file.name}</p>
        <p className="text-xs text-zinc-500 mt-0.5">
          {formatBytes(file.size)} · {file.type || "unknown type"}
        </p>
      </div>
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); onRemove(); }}
        className="grid place-items-center w-8 h-8 rounded-lg text-zinc-500 hover:text-rose-400 hover:bg-rose-500/10 transition-colors flex-shrink-0"
        aria-label="Remove file"
      >
        <XIcon size={16} />
      </button>
    </div>
  );
}

function ErrorBanner({ message, code }: { message: string; code?: string }) {
  return (
    <div className="rounded-xl bg-rose-500/[0.07] border border-rose-500/25 px-4 py-3 flex items-start gap-3 animate-fade-in-up">
      <AlertIcon size={18} className="text-rose-400 flex-shrink-0 mt-0.5" />
      <div className="text-sm text-rose-200 min-w-0">
        {code && <div className="font-mono text-[10px] uppercase tracking-wider text-rose-400/80 mb-0.5">{code}</div>}
        <div className="break-words">{message}</div>
      </div>
    </div>
  );
}
