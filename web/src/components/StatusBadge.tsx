import clsx from "clsx";
import type { JobStatus } from "../api/types";
import { CheckIcon, XIcon, SpinnerIcon, ClockIcon } from "./../lib/icons";

const STYLE: Record<JobStatus, { className: string; icon: React.ReactNode }> = {
  queued: {
    className: "bg-zinc-500/15 text-zinc-300 border-zinc-500/30",
    icon: <ClockIcon size={11} />
  },
  running: {
    className: "bg-amber-500/15 text-amber-300 border-amber-500/40 shadow-[0_0_12px_-4px_rgba(245,158,11,0.5)]",
    icon: <SpinnerIcon size={11} />
  },
  succeeded: {
    className: "bg-emerald-500/15 text-emerald-300 border-emerald-500/40",
    icon: <CheckIcon size={11} />
  },
  failed: {
    className: "bg-rose-500/15 text-rose-300 border-rose-500/40",
    icon: <XIcon size={11} />
  },
  cancelled: {
    className: "bg-zinc-600/20 text-zinc-400 border-zinc-500/30",
    icon: <XIcon size={11} />
  }
};

export function StatusBadge({ status, size = "sm" }: { status: JobStatus; size?: "sm" | "md" }) {
  const cfg = STYLE[status];
  return (
    <span
      className={clsx(
        "inline-flex items-center gap-1.5 rounded-full border font-medium uppercase tracking-wider",
        size === "sm" ? "px-2 py-0.5 text-[10px]" : "px-2.5 py-1 text-xs",
        cfg.className
      )}
    >
      {cfg.icon}
      {status}
    </span>
  );
}
