import clsx from "clsx";
import type { JobStatus } from "../api/types";

const COLOR: Record<JobStatus, string> = {
  queued: "bg-zinc-700 text-zinc-200",
  running: "bg-amber-500/20 text-amber-300 ring-1 ring-amber-500/40",
  succeeded: "bg-emerald-500/20 text-emerald-300 ring-1 ring-emerald-500/40",
  failed: "bg-rose-500/20 text-rose-300 ring-1 ring-rose-500/40",
  cancelled: "bg-zinc-600/30 text-zinc-300 ring-1 ring-zinc-500/40"
};

export function StatusBadge({ status }: { status: JobStatus }) {
  return (
    <span className={clsx("inline-flex items-center px-2 py-0.5 rounded text-xs font-medium uppercase tracking-wide", COLOR[status])}>
      {status}
    </span>
  );
}
