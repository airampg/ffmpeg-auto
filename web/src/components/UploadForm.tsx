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
import { formatBytes } from "../lib/format";

export function UploadForm() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const capabilities = useCapabilities();
  const [file, setFile] = useState<File | null>(null);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [settings, setSettings] = useState<JobSubmitSettings | null>(null);

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
      if (next) setFile(next);
    }
  });

  const submit = () => {
    if (!file || !settings) return;
    setUploadProgress(0);
    mutation.mutate({
      file,
      settings,
      onUploadProgress: (fraction) => setUploadProgress(fraction)
    });
  };

  const error = mutation.error instanceof ApiError ? mutation.error : null;

  return (
    <div className="space-y-4">
      <div
        {...dropzone.getRootProps()}
        className={clsx(
          "border-2 border-dashed rounded p-6 text-center cursor-pointer transition",
          dropzone.isDragActive ? "border-accent bg-accent/5" : "border-zinc-700 hover:border-zinc-500"
        )}
      >
        <input {...dropzone.getInputProps()} />
        {file ? (
          <div>
            <p className="font-medium">{file.name}</p>
            <p className="text-xs text-zinc-500">{formatBytes(file.size)}</p>
            <button
              type="button"
              onClick={(e) => { e.stopPropagation(); setFile(null); }}
              className="mt-2 text-xs text-zinc-400 hover:text-rose-400"
            >
              Remove
            </button>
          </div>
        ) : (
          <p className="text-zinc-400">
            Drop an audio or video file here, or <span className="text-accent">click to browse</span>
          </p>
        )}
      </div>

      {capabilities.isLoading && <p className="text-sm text-zinc-500">Loading capabilities…</p>}
      {capabilities.error && (
        <p className="text-sm text-rose-400">Could not load capabilities. Is the API running?</p>
      )}
      {settings && capabilities.data && (
        <SettingsAdvanced
          capabilities={capabilities.data}
          value={settings}
          onChange={setSettings}
        />
      )}

      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={submit}
          disabled={!file || !settings || mutation.isPending}
          className="bg-accent hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed text-zinc-900 font-medium px-4 py-2 rounded"
        >
          {mutation.isPending ? "Uploading…" : "Start processing"}
        </button>
        {mutation.isPending && (
          <span className="text-xs text-zinc-400">
            Upload {(uploadProgress * 100).toFixed(0)}%
          </span>
        )}
      </div>

      {error && (
        <div className="rounded bg-rose-500/10 border border-rose-500/30 p-3 text-sm text-rose-300">
          <span className="font-mono text-xs uppercase tracking-wide block mb-1">{error.code}</span>
          {error.message}
        </div>
      )}
    </div>
  );
}
