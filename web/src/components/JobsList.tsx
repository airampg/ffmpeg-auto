import { Link } from "react-router-dom";
import { useJobs } from "../hooks/useJobs";
import { StatusBadge } from "./StatusBadge";
import { formatDate } from "../lib/format";
import {
  FileAudioIcon,
  FileVideoIcon,
  FileGenericIcon,
  ChevronLeftIcon
} from "../lib/icons";

function pickIcon(filename: string) {
  const ext = filename.split(".").pop()?.toLowerCase() ?? "";
  if (["mp3", "m4a", "wav", "ogg", "opus", "flac", "aac"].includes(ext)) return FileAudioIcon;
  if (["mp4", "mov", "mkv", "webm", "avi"].includes(ext)) return FileVideoIcon;
  return FileGenericIcon;
}

export function JobsList() {
  const jobs = useJobs();

  if (jobs.isLoading) {
    return (
      <div className="surface-card p-6 text-sm text-zinc-500">Loading jobs…</div>
    );
  }
  if (jobs.error) {
    return (
      <div className="rounded-xl bg-rose-500/[0.07] border border-rose-500/25 p-4 text-sm text-rose-200">
        Could not load jobs.
      </div>
    );
  }
  if (!jobs.data || jobs.data.length === 0) {
    return (
      <div className="surface-card p-10 text-center">
        <p className="text-sm text-zinc-400">No jobs yet.</p>
        <p className="text-xs text-zinc-600 mt-1">Upload a file above to start.</p>
      </div>
    );
  }

  return (
    <div className="surface-card divide-y divide-white/[0.05] overflow-hidden">
      {jobs.data.map((job) => {
        const Icon = pickIcon(job.inputFilename);
        return (
          <Link
            key={job.jobId}
            to={`/jobs/${job.jobId}`}
            className="flex items-center gap-4 px-5 py-3.5 hover:bg-[var(--surface-2)] transition-colors group"
          >
            <div className="grid place-items-center w-9 h-9 rounded-lg bg-[var(--surface-3)] text-zinc-400 group-hover:text-[var(--color-accent)] group-hover:bg-[var(--color-accent-soft)] transition-colors flex-shrink-0">
              <Icon size={18} />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="font-medium text-zinc-100 truncate">{job.inputFilename}</span>
              </div>
              <div className="flex items-center gap-2 text-[11px] text-zinc-500 mt-0.5">
                <span className="font-mono">{job.jobId.slice(0, 8)}</span>
                <span className="text-zinc-700">·</span>
                <span>{formatDate(job.createdAt)}</span>
              </div>
            </div>
            <StatusBadge status={job.status} />
            <ChevronLeftIcon
              size={14}
              className="text-zinc-600 group-hover:text-zinc-300 rotate-180 transition-colors"
            />
          </Link>
        );
      })}
    </div>
  );
}
