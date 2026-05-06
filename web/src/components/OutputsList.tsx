import { outputDownloadURL, zipDownloadURL } from "../api/jobs";
import type { JobOutput } from "../api/types";
import { formatBytes } from "../lib/format";
import {
  DownloadIcon,
  ArchiveIcon,
  FileAudioIcon,
  FileVideoIcon,
  FileGenericIcon
} from "../lib/icons";

function pickIcon(name: string) {
  const ext = name.split(".").pop()?.toLowerCase() ?? "";
  if (["mp3", "m4a", "wav", "ogg", "opus", "flac", "aac"].includes(ext)) return FileAudioIcon;
  if (["mp4", "mov", "mkv", "webm", "avi"].includes(ext)) return FileVideoIcon;
  return FileGenericIcon;
}

export function OutputsList({ jobId, outputs }: { jobId: string; outputs: JobOutput[] }) {
  if (outputs.length === 0) {
    return (
      <div className="surface-card p-6 text-sm text-zinc-500 text-center">No outputs yet.</div>
    );
  }
  return (
    <div className="space-y-3">
      <a
        href={zipDownloadURL(jobId)}
        download={`${jobId}.zip`}
        className="btn-primary inline-flex items-center gap-2 text-sm"
      >
        <ArchiveIcon size={14} />
        Download all as zip
      </a>
      <ul className="grid grid-cols-1 sm:grid-cols-2 gap-2">
        {outputs.map((output) => {
          const Icon = pickIcon(output.name);
          return (
            <li
              key={output.name}
              className="surface-card flex items-center gap-3 px-4 py-3 group hover:border-white/10 transition-colors"
            >
              <div className="grid place-items-center w-9 h-9 rounded-lg bg-[var(--surface-3)] text-zinc-400 group-hover:text-[var(--color-accent)] group-hover:bg-[var(--color-accent-soft)] transition-colors flex-shrink-0">
                <Icon size={18} />
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-mono text-xs truncate text-zinc-100">{output.name}</p>
                <p className="text-[10px] text-zinc-500 mt-0.5">{formatBytes(output.sizeBytes)}</p>
              </div>
              <a
                href={outputDownloadURL(jobId, output.name)}
                download
                className="grid place-items-center w-8 h-8 rounded-lg text-zinc-400 hover:text-[var(--color-accent)] hover:bg-[var(--color-accent-soft)] transition-colors flex-shrink-0"
                aria-label={`Download ${output.name}`}
              >
                <DownloadIcon size={16} />
              </a>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
